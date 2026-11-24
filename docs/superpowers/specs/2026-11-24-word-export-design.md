# Word Document Export — Design

Date: 2026-11-24
Branch: `word-export`

## Intent

Add a Word (`.docx`) export for a specific counterparty, aimed at legal review: a person exports every direct conversation with one person, opens the result in Word, searches it, highlights passages, and edits notes around the messages.

Also fix export concurrency: exports currently can overlap, and the running export reads `AppState.messages` after the user may have changed the selected conversation. Exports must be modal, show real progress with a time estimate, and be cancellable.

Once the `.docx` export is correct, make it substantially faster.

## Goals

- Export all direct (1:1) conversations with one counterparty into a single `.docx`.
- Include the same content the PDF has: timestamps, sender, service, delivered/read, reactions, thread markers, attachments, and optionally inline images.
- Produce real Word structure: cover page, Heading 1 per conversation, date separators, editable body paragraphs, footer page numbers. The document must be searchable and highlightable in Word or Pages.
- Make every export modal, with determinate progress, message counts, ETA, and Cancel.
- Prevent a second export from starting while one runs.
- Prove correctness with tests, and measure performance on real data before and after optimization.

## Non-goals

- Group chats in the "all conversations with counterparty" set. Jesse chose direct chats only.
- OCR, transcript cleanup, redaction, or legal line numbering.
- A PDF redesign. PDF keeps its current layout; it gains the shared modal/progress/cancel behavior.
- Changing conversation selection behavior. It works today.
- Batch export for several counterparties at once.

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

### 1. Export scope

`ExportScope`:

- `.thisConversation` — the selected chat, group or 1:1.
- `.allDirectWithCounterparty` — every chat with exactly one participant whose handle belongs to the selected counterparty.

Counterparty identity:

- Start from the selected 1:1 chat's sole participant handle.
- If Contacts access is available, expand to every handle in the app's conversation list that resolves to the same `CNContact.identifier`. This catches a person's second phone number or email.
- If Contacts access is absent, use the exact handle only.
- Always include the selected conversation.
- Sort conversations by first-message date ascending. Exclude chats with zero messages.
- A group chat selected in the sidebar can export `.thisConversation`; `.allDirectWithCounterparty` is offered only for 1:1 selections because a group has no single counterparty.

The Word export sheet shows the resolved names and handles and a live summary: conversation count, message count, image count. Defaults: scope = all direct conversations when available, images = thumbnails.

### 2. Shared export data pipeline

New export path, separate from the UI's progressive message loader:

- `ExportPlanner` takes `[ConversationInfo]` plus `DatabaseService` and produces `[ExportConversation]`.
- `ExportConversation` holds name, service, participants, and `[ExportMessage]`.
- `ExportMessage` mirrors `DisplayMessage` without AppKit image objects. Attachments carry path, MIME, size, and image dimensions, not `NSImage`.
- Text still comes from `text` or `AttributedBodyParser`.
- Reactions are aggregated per chat with the existing `ReactionAggregator`.
- `DatabaseService` gains a bulk attachment fetch: one query for all messages in all selected chats, returned keyed by message ROWID. This removes the current N+1 `fetchAttachments` per message.
- This pipeline is used by both PDF and Word export, so the PDF also stops doing N+1 queries. The UI loader keeps its current selection behavior.

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

- Cover: title "Conversations with <Name>", export date, conversation count, message count, date range, participant handles, image mode.
- One section per conversation, page break before each except the first:
  - Heading 1: conversation display name and service.
  - Metadata line: participants, date range, message count.
  - Date separators.
  - Per message:
    - Meta paragraph: time, sender, sender handle when different, service, delivered/read, edited/unsent.
    - Body paragraph: exact message text, editable, searchable, one paragraph per message. Newlines become `<w:br/>`.
    - Reaction paragraph: emoji and reactor names.
    - Thread-reply marker.
    - Attachment paragraph: icon, filename, size.
    - Inline image paragraph when images are enabled.
  - System messages use an italic gray style.
- Footer: "<Name> — Page X of Y" using PAGE/NUMPAGES fields.

Styles: Normal, Title, Heading 1, MessageMeta, MessageBody, DateSeparator, Reaction, Attachment, SystemMessage. Meta and body use `keepNext` so a sender line does not strand at a page bottom.

Images:

- PNG and JPEG embed their original bytes when full resolution is selected.
- HEIC/GIF/other formats convert to JPEG at quality 0.9 for Word compatibility.
- Thumbnails use ImageIO (`CGImageSourceCreateThumbnailAtIndex`) at max 640×480, JPEG quality 0.85.
- Display size comes from pixel dimensions at 96 DPI, capped at 4.5" wide and 6" tall.
- Undecodable images produce a filename label, not a failure.

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

- `Export PDF…` — existing save panel and image accessory.
- `Export Word Document…` — open the Word export sheet above.

Flow: configure (Word only) → save panel → modal progress panel → open the file.

`ExportProgressPanel` is an AppKit panel shown with `NSApp.runModal(for:)`, so it is app-modal. It shows:

- Determinate progress bar over weighted work units.
- Phase line: "Preparing", "Rendering messages", "Writing images", "Compressing".
- Count line: "Rendering 3,200 of 10,994 messages".
- ETA line: "About 20 seconds remaining", suppressed below 10% completion.
- Cancel button.

`ExportSession` owns the export task, a cancellation flag, and progress state. It is the only entry point for exports. `AppState.beginExport()` returns false if a session is active. This is the overlap fix, independent of UI disabling. The selected `messages` are captured before the task starts. The progress panel's `runModal` also blocks the rest of the app.

ETA uses weighted units: each message is 1, each prepared image is 3. Completion time is measured from the session start; ETA = elapsed / fraction − elapsed, smoothed over recent samples.

Cancellation:

- Checked at message boundaries, per image, and before zip.
- Temp files and partial output removed.
- Panel reports "Cancelled" and closes.

### 5. Performance

Correctness first, then measure and optimize.

Baseline targets on the largest real direct chat (chat 2: 10,994 messages, 750 images, 1.4 GB originals):

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

A benchmark test gated by `IMESSAGEPRINTER_BENCHMARK=1` reads the real database, exports the largest direct chat in each image mode, and prints wall time and output size. It runs locally; CI skips it when the database is unavailable.

### 6. Tests

Add `Tests/iMessagePrinterTests` and a `.testTarget` in `Package.swift`.

Unit tests:

- XML escaping, control-character stripping, newline handling.
- ZIP/package structure: unzip and assert required parts, valid XML, and `unzip -t` success.
- Generated document contains expected message text, sender, date, reaction, and attachment label.
- Generated document embeds an image and a relationship entry.
- `textutil -convert txt` reads the generated file and returns the message text.
- Scope resolution: 1:1, group, second handle from the same contact, Contacts unavailable.
- Progress estimator math and ETA suppression.
- Planner against a temporary SQLite fixture: reactions, bulk attachments, sender names, missing text with `attributedBody`.

Manual acceptance:

- Export a real counterparty with several direct chats.
- Open in Pages (and Word if available): headings appear in navigation, text is editable, search finds a known phrase, highlights work, images render, footer page numbers update.
- Start a second export while one runs: it is rejected or blocked.
- Cancel an export: no destination file remains.
- Confirm selection changes during export do not affect the exported messages.

## Files

- `Sources/iMessagePrinter/Services/Export/ExportModels.swift`
- `Sources/iMessagePrinter/Services/Export/ExportPlanner.swift`
- `Sources/iMessagePrinter/Services/Export/ExportSession.swift`
- `Sources/iMessagePrinter/Services/Export/DocxWriter.swift`
- `Sources/iMessagePrinter/Services/Export/DocxExportService.swift`
- `Sources/iMessagePrinter/Services/Export/ImagePreparer.swift`
- `Sources/iMessagePrinter/Services/Export/ZipPackager.swift`
- `Sources/iMessagePrinter/Views/WordExportSheet.swift`
- `Sources/iMessagePrinter/Views/ExportProgressPanel.swift` (AppKit controller)
- `Sources/iMessagePrinter/Services/DatabaseService.swift` (bulk fetch, injectable path)
- `Sources/iMessagePrinter/Services/PDFExportService.swift` (shared model, progress, cancel)
- `Sources/iMessagePrinter/App/AppState.swift` (scope, session, menu actions)
- `Sources/iMessagePrinter/Views/MessageDetailView.swift` (Export menu, remove old bool overlay)
- `Package.swift` (test target)
- `Tests/iMessagePrinterTests/*`

## Acceptance

- Word export from a selected 1:1 conversation writes a `.docx` containing every direct chat with that counterparty, with correct text and metadata.
- The file opens in Pages and `textutil` without repair prompts, has working Heading 1 navigation, editable/searchable body text, and embedded images.
- Export is modal with determinate progress, message counts, ETA, and working Cancel.
- Two exports cannot run at once, and changing selection mid-export cannot change the exported data.
- Large-export performance is measured before and after optimization, with numbers recorded in the final report.

## Calls made without asking

- Direct chats only for counterparty scope, per Jesse's answer.
- Separate section per conversation rather than one interleaved timeline.
- Default image mode is thumbnails.
- Group chats can be exported with the "this conversation" scope.
- No new dependency; system `zip` and ImageIO are sufficient.
- PDF layout is unchanged; only its modal progress and data pipeline change.
