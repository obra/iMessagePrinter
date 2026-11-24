# Word Document Export — Design

Date: 2026-11-24
Branch: `word-export`

## Intent

Add a Word (`.docx`) export so the selected conversation can be opened in Word, searched, highlighted, and annotated. This is aimed at legal review, where someone reads one long thread and marks passages.

Both PDF and Word export the currently selected conversation only. There is no cross-chat aggregation and no change to conversation selection behavior.

Also fix export concurrency: exports currently can overlap, and the running export reads `AppState.messages` after the user may have changed the selected conversation. Exports must be modal, show real progress with a time estimate, and be cancellable.

Once the `.docx` export is correct, make it substantially faster.

## Goals

- Export the selected conversation to `.docx` as one chronological, editable, searchable timeline.
- Include the same content the PDF has: timestamps, sender, service, delivered/read, reactions, thread markers, attachments, and optionally inline images.
- Produce real Word structure: cover page, a Heading 1 conversation title, month headings for navigation, date separators, editable body paragraphs, footer page numbers.
- Make every export modal, with determinate progress, message counts, ETA, and Cancel.
- Prevent a second export from starting while one runs.
- Prove correctness with tests, and measure performance on real data before and after optimization.

## Non-goals

- Exporting multiple chats or all chats with a counterparty in one document. Both formats export this conversation only.
- Grouping the Word document into one section per chat. It is one chronological timeline.
- Changing conversation selection behavior. It works today.
- OCR, transcript cleanup, redaction, or legal line numbering.
- A PDF layout redesign. PDF keeps its current layout; it gains the shared modal/progress/cancel behavior.
- Batch export for several conversations at once.

## Constraints

- macOS 14+, Swift 5.10 package, AppKit + SwiftUI.
- No sandbox; Full Disk Access is already required for `~/Library/Messages/chat.db`.
- Existing PDF export is `PDFExportService` and uses `DisplayMessage`.
- There are no tests today. Add a test target.
- Do not add a new package dependency unless the system tools prove insufficient.

## Approaches considered

### A. Generate OOXML directly and zip with `/usr/bin/zip` (chosen)

A `.docx` is a ZIP of XML parts. Generate `[Content_Types].xml`, `_rels/.rels`, `word/document.xml`, `word/styles.xml`, `word/_rels/document.xml.rels`, footer, and `word/media/*`, then zip a staging directory.

Trades off ~500 lines of XML plumbing against full control of styles, headings, image sizing, and progress boundaries. No dependency. Easy to test by unzipping and by opening with `textutil`, Pages, or `qlmanage`.

### B. Add a Swift docx/ZIP library

Pulls in a dependency for ZIP and document construction. Saves packaging code, but most libraries either do not support inline images or hide the XML enough that Word-compatibility surprises are harder to diagnose. Adds CI and bundle-resource work. Rejected for this size of feature.

### C. Generate RTF or HTML, convert with `textutil`

Fewer lines initially. Loses precise heading/style control, image placement is awkward, and conversion speed and fidelity are less predictable. Rejected.

## Design

### 1. Export target

Both `Export PDF…` and `Export Word Document…` capture the selected `ConversationInfo` and plan that one chat from a fresh database read.

- The planner reads the chat's messages once at export start. A selection change during export cannot change the output.
- The UI's progressive `AppState.messages` list is not used as the export source. It and the planner read the same rows, but the planner snapshot is self-contained.
- PDF keeps its current scope and layout.
- Word uses the same snapshot and writes one document.

### 2. Shared export data pipeline

New export path, separate from the UI's progressive message loader:

- `ExportPlanner` takes one `ConversationInfo` plus `DatabaseService` and produces one `ExportConversation`.
- `ExportConversation` holds name, service, participants, and `[ExportMessage]`.
- `ExportMessage` mirrors `DisplayMessage` without AppKit image objects. Attachments carry path, MIME, size, and image dimensions, not `NSImage`.
- Text still comes from `text` or `AttributedBodyParser`.
- Reactions are aggregated with the existing `ReactionAggregator`.
- `DatabaseService` gains a bulk attachment fetch: one query for all messages in the chat, returned keyed by message ROWID. This removes the current N+1 `fetchAttachments` per message.
- Both PDF and Word consume this pipeline. PDF also stops doing N+1 queries. The UI loader keeps its current behavior.

### 3. `.docx` writer

Package parts:

```
[Content_Types].xml
_rels/.rels
word/document.xml
word/styles.xml
word/_rels/document.xml.rels
word/footer1.xml
word/media/imageN.png|jpg
docProps/core.xml
docProps/app.xml
```

Document structure:

- Cover: title "Conversation with <Name>", export date, participant handles, service, message count, date range, image mode.
- Page break.
- Heading 1: conversation display name. This is the only top-level navigation entry.
- Heading 2 per calendar month, in chronological order.
- Date separator for each calendar day.
- Per message, in chronological order:
  - Meta paragraph: time, sender, sender handle when different, service, delivered/read, edited/unsent.
  - Body paragraph: exact message text, editable, searchable, one paragraph per message. Newlines become `<w:br/>`.
  - Reaction paragraph: emoji and reactor names.
  - Thread-reply marker.
  - Attachment paragraph: icon, filename, size.
  - Inline image paragraph when images are enabled.
- System messages use an italic gray style.
- Footer: "<Name> — Page X of Y" using PAGE/NUMPAGES fields.

Styles: Normal, Title, Heading 1, Heading 2, MessageMeta, MessageBody, DateSeparator, Reaction, Attachment, SystemMessage. Meta and body use `keepNext` so a sender line does not strand at a page bottom.

Images:

- PNG and JPEG embed their original bytes when full resolution is selected.
- HEIC/GIF/other formats convert to JPEG at quality 0.9 for Word compatibility.
- Thumbnails use ImageIO (`CGImageSourceCreateThumbnailAtIndex`) at max 640×480, JPEG quality 0.85.
- Display size comes from pixel dimensions at 96 DPI, capped at 4.5" wide and 6" tall.
- An attachment is an exportable image when `mime_type` starts with `image/`, it has a resolved path, and the file exists. `transfer_state` is not used. This is the same predicate for the progress denominator and the writer.
- Undecodable or missing images produce a filename label, not a failure.

Text safety:

- XML-escape `& < > "`.
- Strip XML-invalid control characters.
- Preserve spaces with `xml:space="preserve"`.

Packaging:

- Render into a UUID-named staging directory in the system temp directory.
- Zip with `/usr/bin/zip -X -q -0 -r <temp.docx> . -x '.*'` from the staging directory.
- Store entries uncompressed (`-0`). Images are already compressed; XML is small. This avoids wasting CPU on deflate and is a speed decision. Benchmark against `-1` and keep the faster option that opens correctly.
- Move the finished archive to the user's destination after a successful zip. Delete staging on success, cancel, and error.

### 4. Modal export UI and progress

Toolbar becomes an `Export` menu:

- `Export PDF…` — save panel with the existing image accessory.
- `Export Word Document…` — the same save panel and image accessory, with a `.docx` content type and filename.

Flow: save panel with image options → modal progress panel → open the file.

`ExportProgressPanel` is an AppKit panel shown with `NSApp.runModal(for:)`, so it is app-modal. It shows:

- Determinate progress bar over weighted work units.
- Phase line: "Preparing", "Rendering messages", "Writing images", "Compressing".
- Count line: "Rendering 3,200 of 10,994 messages".
- ETA line: "About 20 seconds remaining", suppressed below 10% completion.
- Cancel button.

`ExportSession` owns the export task, a cancellation flag, and progress state. It is the only entry point for exports. `AppState.beginExport()` returns false if a session is active. This is the overlap fix, independent of UI disabling. The selected conversation and image mode are captured before the task starts. The progress panel's `runModal` also blocks the rest of the app.

ETA uses weighted units: each message is 1, each prepared image is 3. Completion time is measured from the session start; ETA = elapsed / fraction − elapsed, smoothed over recent samples.

Cancellation:

- Checked at message boundaries, per image, and before zip.
- Temp files and partial output removed.
- Panel reports "Cancelled" and closes.

### 5. Performance

Correctness first, then measure and optimize.

Baseline targets on the largest real conversation (chat 2: 10,994 messages, 750 exportable images, 1.4 GB of existing image files):

- No images: under 3 seconds.
- Thumbnails: under 10 seconds.
- Full resolution: under 30 seconds.

These are goals to report against, not promises.

Optimizations, in order:

1. Bulk attachment query instead of one query per message.
2. No `NSImage` in the export path; metadata-only sizing and on-demand decode.
3. Prepare images in parallel across cores, writing media files directly to staging.
4. Single-pass XML assembly with reserved capacity and cached date formatters.
5. Store media uncompressed in the ZIP and fast-deflate or store XML.
6. Reuse the same planner and bulk fetch for PDF, and measure whether PDF also improves.

A benchmark test gated by `IMESSAGEPRINTER_BENCHMARK=1` reads the real database, exports the largest conversation in each image mode, and prints wall time and output size. It runs locally; CI skips it when the database is unavailable.

### 6. Builder-check resolutions

The independent builder check raised four questions. They are resolved here:

1. Scope is one conversation, per Jesse's correction. There is no all-direct counterparty scope, so the direct-chat predicate and partial-conversation-list issues disappear.
2. The selected conversation is captured at click time. Both formats plan from a fresh database snapshot, so selection changes cannot alter the output and no partially loaded UI list is involved.
3. Both PDF and Word read messages from the planner snapshot. PDF stays this-conversation only.
4. Image counts and embedding use the same predicate: `image/*`, a resolved path, and an existing file. `transfer_state` is ignored. Chat 2 has 855 `image/*` rows but only 750 existing files; 750 is the exportable count, and the rest are labeled only.

### 7. Tests

Add `Tests/iMessagePrinterTests` and a `.testTarget` in `Package.swift`.

Unit tests:

- XML escaping, control-character stripping, newline handling.
- ZIP/package structure: unzip and assert required parts, valid XML, and `unzip -t` success.
- Generated document contains expected message text, sender, date, reaction, and attachment label.
- Generated document embeds an image and a relationship entry.
- Generated document is one chronological timeline with the expected month headings and date separators.
- `textutil -convert txt` reads the generated file and returns the message text.
- Progress estimator math and ETA suppression.
- Planner against a temporary SQLite fixture: reactions, bulk attachments, sender names, missing text with `attributedBody`, and a snapshot that ignores later DB changes.
- Planner only reads the selected chat; messages from another chat are absent.

Manual acceptance:

- Export a real conversation to Word with several thousand messages and images.
- Open in Pages (and Word if available): the conversation title is in navigation, text is editable, search finds a known phrase, highlights work, images render, footer page numbers update.
- Confirm the document is one timeline, not one section per chat.
- Start a second export while one runs: it is rejected or blocked.
- Cancel an export: no destination file remains.
- Change the selected conversation during export: the exported file still contains the original conversation.

## Files

- `Sources/iMessagePrinter/Services/Export/ExportModels.swift`
- `Sources/iMessagePrinter/Services/Export/ExportPlanner.swift`
- `Sources/iMessagePrinter/Services/Export/ExportSession.swift`
- `Sources/iMessagePrinter/Services/Export/DocxWriter.swift`
- `Sources/iMessagePrinter/Services/Export/DocxExportService.swift`
- `Sources/iMessagePrinter/Services/Export/ImagePreparer.swift`
- `Sources/iMessagePrinter/Services/Export/ZipPackager.swift`
- `Sources/iMessagePrinter/Views/ExportProgressPanel.swift` (AppKit controller)
- `Sources/iMessagePrinter/Services/DatabaseService.swift` (bulk attachment fetch, injectable path for tests)
- `Sources/iMessagePrinter/Services/PDFExportService.swift` (shared model, progress, cancel)
- `Sources/iMessagePrinter/App/AppState.swift` (session, save panels, menu actions)
- `Sources/iMessagePrinter/Views/ExportAccessoryView.swift` (used by both formats)
- `Sources/iMessagePrinter/Views/MessageDetailView.swift` (Export menu, remove old bool overlay)
- `Package.swift` (test target)
- `Tests/iMessagePrinterTests/*`

## Acceptance

- Word export from the selected conversation writes a `.docx` containing that conversation as one chronological timeline.
- The file opens in Pages and `textutil` without repair prompts, has a working conversation heading, month headings, editable/searchable body text, and embedded images.
- Export is modal with determinate progress, message counts, ETA, and working Cancel.
- Two exports cannot run at once, and changing selection mid-export cannot change the exported data.
- Large-export performance is measured before and after optimization, with numbers recorded in the final report.

## Calls made

- Both formats export this conversation only, per Jesse's correction.
- One chronological timeline with month headings, not one section per chat.
- Default image mode is thumbnails.
- No new dependency; system `zip` and ImageIO are sufficient.
- PDF layout is unchanged; only its modal progress and data pipeline change.
