# Word Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Export the selected conversation to an editable, searchable `.docx` timeline, make all exports modal with progress and cancel, and measure then speed up Word export.

**Architecture:** Both formats plan one conversation from a fresh database snapshot into shared `ExportMessage` models. A pure OOXML writer produces the Word package, ImageIO prepares media, and `/usr/bin/zip` packages it. An app-modal AppKit panel drives a single cancellable export session.

**Tech Stack:** Swift 5.10, macOS 14+, GRDB, AppKit, SwiftUI, ImageIO, XCTest, system `zip`, `textutil`.

**Spec:** `docs/superpowers/specs/2026-11-24-word-export-design.md`

## Global Constraints

- macOS 14+, Swift 5.10 package, AppKit + SwiftUI.
- No new package dependency. Use ImageIO and `/usr/bin/zip`.
- Both PDF and Word export the selected conversation only.
- No change to conversation selection behavior.
- Exports are app-modal, show determinate progress and ETA, and are cancellable.
- A second export cannot start while one is active.
- The export source is a fresh database snapshot taken at export start, not `AppState.messages`.
- Word output is one chronological timeline, not one section per chat.
- Default image mode is thumbnails.
- Every task ends with a green test run and a commit.

## Review Focus

- Message text containing `&`, `<`, `>`, quotes, emoji, tabs, or newlines must appear exactly, and the `.docx` must open without repair.
- Missing, undecodable, HEIC, or very large images must produce a label or a valid embedded image, never a corrupt package or a crash.
- A 10,000+ message conversation must keep the UI responsive, show moving progress, and not blow up memory.
- Changing the selected conversation during an export must not change the exported conversation.
- Cancelling or starting a second export must leave no partial destination file and must not let two exports run.

---

### Task 1: Test Target and XML Text Safety

**Files:**
- Modify: `Package.swift`
- Create: `Sources/iMessagePrinter/Services/Export/XMLText.swift`
- Create: `Tests/iMessagePrinterTests/XMLTextTests.swift`

**Interfaces:**
- Produces: `enum XMLText { static func escape(_ s: String) -> String; static func runs(_ s: String) -> String }`
- Produces: `.testTarget(name: "iMessagePrinterTests", dependencies: ["iMessagePrinter"], path: "Tests/iMessagePrinterTests")`

- [ ] **Step 1: Add the test target**

Add to `Package.swift` after the executable target:

```swift
.testTarget(
    name: "iMessagePrinterTests",
    dependencies: ["iMessagePrinter"],
    path: "Tests/iMessagePrinterTests"
)
```

- [ ] **Step 2: Write the failing tests**

`Tests/iMessagePrinterTests/XMLTextTests.swift`:

```swift
import XCTest
@testable import iMessagePrinter

final class XMLTextTests: XCTestCase {
    func testEscapesMarkupCharacters() {
        XCTAssertEqual(
            XMLText.escape("a & b < c > d \"e\" 'f'"),
            "a &amp; b &lt; c &gt; d &quot;e&quot; 'f'"
        )
    }

    func testStripsInvalidControlCharacters() {
        let input = "a\u{0000}b\u{0008}c\u{000B}d\u{001F}e"
        XCTAssertEqual(XMLText.escape(input), "abcde")
    }

    func testRunsTurnNewlinesAndTabsIntoWordMarkup() {
        XCTAssertEqual(
            XMLText.runs("line 1\nline 2\tend"),
            "line 1<w:br/>line 2<w:tab/>end"
        )
    }

    func testRunsPreserveEmojiAndAmpersands() {
        XCTAssertEqual(XMLText.runs("❤️ & more"), "❤️ &amp; more")
    }

    func testRunsHandleCarriageReturnNewline() {
        XCTAssertEqual(XMLText.runs("a\r\nb"), "a<w:br/>b")
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --filter XMLTextTests`
Expected: compile failure, `XMLText` is not defined.

- [ ] **Step 4: Implement `XMLText`**

`XMLText.escape` replaces, in order, `&` then `<`, `>`, `"`, and removes code points `0x00-0x08`, `0x0B`, `0x0C`, `0x0E-0x1F`. `XMLText.runs` normalizes `\r\n` to `\n`, escapes the non-newline segments, and joins with `<w:br/>` for `\n` and `<w:tab/>` for `\t`.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter XMLTextTests`
Expected: 5 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/iMessagePrinter/Services/Export/XMLText.swift Tests/iMessagePrinterTests/XMLTextTests.swift
git commit -m "test: add export test target and XML text helpers"
```

---

### Task 2: Export Models and Progress Estimator

**Files:**
- Create: `Sources/iMessagePrinter/Services/Export/ExportModels.swift`
- Create: `Sources/iMessagePrinter/Services/Export/ExportProgress.swift`
- Create: `Tests/iMessagePrinterTests/ExportProgressEstimatorTests.swift`

**Interfaces:**
- Produces: `enum ExportImageMode: Int, CaseIterable { case omit = 0, thumbnail = 1, fullResolution = 2; var label: String }`
- Produces: `struct ExportAttachment`, `struct ExportMessage`, `struct ExportConversation`
- Produces: `struct ExportProgress { enum Phase { case preparing, rendering, images, compressing, finishing }; var phase: Phase; var fraction: Double; var processedMessages: Int; var totalMessages: Int; var processedImages: Int; var totalImages: Int; var estimatedRemaining: TimeInterval? }`
- Produces: `struct ExportProgressEstimator { init(totalMessages: Int, totalImages: Int, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }); mutating func setPhase(_:); mutating func messageCompleted(); mutating func imageCompleted(); var snapshot: ExportProgress }`
- Produces: `enum ExportFormat { case pdf, docx; var fileExtension: String; var defaultNameSuffix: String }`

- [ ] **Step 1: Write the failing progress tests**

`Tests/iMessagePrinterTests/ExportProgressEstimatorTests.swift`:

```swift
import XCTest
@testable import iMessagePrinter

final class ExportProgressEstimatorTests: XCTestCase {
    func testFractionUsesMessageAndImageWeights() {
        var now: TimeInterval = 0
        var e = ExportProgressEstimator(totalMessages: 10, totalImages: 2, now: { now })
        for _ in 0..<5 { e.messageCompleted() }
        e.imageCompleted()
        XCTAssertEqual(e.snapshot.fraction, (5.0 + 3.0) / 16.0, accuracy: 0.0001)
        XCTAssertEqual(e.snapshot.processedMessages, 5)
        XCTAssertEqual(e.snapshot.processedImages, 1)
    }

    func testEstimateAppearsAfterTenPercent() {
        var now: TimeInterval = 0
        var e = ExportProgressEstimator(totalMessages: 100, totalImages: 0, now: { now })
        for _ in 0..<5 { e.messageCompleted() }
        now = 10
        XCTAssertNil(e.snapshot.estimatedRemaining)

        for _ in 0..<45 { e.messageCompleted() }
        now = 20
        let remaining = try XCTUnwrap(e.snapshot.estimatedRemaining)
        XCTAssertEqual(remaining, 20, accuracy: 1.0)
    }

    func testFractionNeverExceedsOne() {
        var e = ExportProgressEstimator(totalMessages: 2, totalImages: 0)
        for _ in 0..<5 { e.messageCompleted() }
        XCTAssertEqual(e.snapshot.fraction, 1.0, accuracy: 0.0001)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ExportProgressEstimatorTests`
Expected: compile failure, `ExportProgressEstimator` is not defined.

- [ ] **Step 3: Implement the models and estimator**

Define the types above. `ExportAttachment` carries `id`, `filename`, `transferName`, `mimeType`, `totalBytes`, `isImage`, `resolvedPath`, `formattedSize`. `ExportMessage` mirrors `DisplayMessage` fields without `NSImage`. `ExportConversation` carries `chatRowID`, `chatGUID`, `displayName`, `participants`, `participantNames`, `serviceName`, `isGroupChat`, `messages`.

Estimator rules: weight a message as 1 unit and an image as 3. Total units = messages + 3 × images. `fraction` clamps to 0...1. ETA is `(remainingUnits / rate)`, where `rate` is taken from the last up to 20 samples of completed units over elapsed time. Suppress ETA while `fraction < 0.1` or `rate <= 0`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter ExportProgressEstimatorTests`
Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/iMessagePrinter/Services/Export/ExportModels.swift Sources/iMessagePrinter/Services/Export/ExportProgress.swift Tests/iMessagePrinterTests/ExportProgressEstimatorTests.swift
git commit -m "feat: add export models and progress estimator"
```

---

### Task 3: Database Fixture and Export Planner

**Files:**
- Modify: `Sources/iMessagePrinter/Services/DatabaseService.swift`
- Create: `Sources/iMessagePrinter/Services/Export/ExportPlanner.swift`
- Create: `Tests/iMessagePrinterTests/TestSupport.swift`
- Create: `Tests/iMessagePrinterTests/ExportPlannerTests.swift`

**Interfaces:**
- Produces: `DatabaseService.init(path: String = DatabaseService.chatDBPath) throws`
- Produces: `struct ExportPlanner { init(db: DatabaseService, handleMap: [Int64: HandleRecord], contactResolver: ContactResolver); func plan(conversation: ConversationInfo, imageMode: ExportImageMode, progress: @escaping (ExportProgress) -> Void, isCancelled: @escaping () -> Bool) throws -> ExportConversation }`
- Produces: `final class CancelFlag: @unchecked Sendable { func cancel(); var isCancelled: Bool }`

- [ ] **Step 1: Make the database path injectable**

Change `init()` to:

```swift
init(path: String = DatabaseService.chatDBPath) throws {
    var config = Configuration()
    config.readonly = true
    dbQueue = try DatabaseQueue(path: path, configuration: config)
}
```

- [ ] **Step 2: Write the fixture and failing planner tests**

`Tests/iMessagePrinterTests/TestSupport.swift` creates a temporary SQLite file with the tables and columns used by `DatabaseService`: `handle`, `chat`, `chat_handle_join`, `message`, `chat_message_join`, `attachment`, `message_attachment_join`. Expose:

```swift
struct Fixture {
    let directory: URL
    let dbPath: String
    let db: DatabaseService
}

func makeFixture() throws -> Fixture
```

Insert two chats: chat 1 has messages 1-3 from handle 10, chat 2 has message 4 from handle 10. Include one reaction, one attachment, and one message whose `text` is nil but `attributedBody` is a typedstream fixture.

`ExportPlannerTests.swift`:

```swift
func testPlansOnlyTheSelectedChat() throws {
    let f = try makeFixture()
    let conversation = try fixtureConversation(f, chatRowID: 1)
    let plan = try ExportPlanner(db: f.db, handleMap: try f.db.fetchAllHandles(), contactResolver: ContactResolver())
        .plan(conversation: conversation, imageMode: .omit, progress: { _ in }, isCancelled: { false })
    XCTAssertEqual(plan.messages.map(\.id), [1, 2, 3])
    XCTAssertFalse(plan.messages.contains { $0.id == 4 })
}

func testAttachesReactionsToTheTargetMessage() throws { ... }

func testParsesAttributedBodyWhenTextIsNil() throws { ... }

func testReportsMessagesWithAttachments() throws {
    let plan = try makePlan(imageMode: .omit)
    XCTAssertEqual(plan.messages.first { $0.id == 2 }?.attachments.count, 1)
}

func testSnapshotIgnoresLaterDatabaseChanges() throws {
    let f = try makeFixture()
    let plan = try planChat1(f)
    try f.db.executeForTest("UPDATE message SET text = 'changed' WHERE ROWID = 1")
    XCTAssertEqual(plan.messages.first?.text, "original")
}
```

Add a small test-only helper `executeForTest(_ sql: String)` to `DatabaseService` or use `GRDB` directly in the test.

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --filter ExportPlannerTests`
Expected: compile failure, `ExportPlanner` is not defined.

- [ ] **Step 4: Implement `ExportPlanner` and `CancelFlag`**

Plan steps: fetch `MessageRecord`s, aggregate reactions with `ReactionAggregator`, build sender names from `handleMap` and `contactResolver`, parse `attributedBody` with `AttributedBodyParser`, fetch attachments with the existing `fetchAttachments(messageRowID:)` once per message, map `AttachmentRecord` into `ExportAttachment`, skip reaction and reaction-removal rows, and report progress every 250 messages. Check `isCancelled()` before each message and throw `CancellationError`.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter ExportPlannerTests`
Expected: all planner tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/iMessagePrinter/Services/DatabaseService.swift Sources/iMessagePrinter/Services/Export/ExportPlanner.swift Tests/iMessagePrinterTests/TestSupport.swift Tests/iMessagePrinterTests/ExportPlannerTests.swift
git commit -m "feat: add export planner with fixture tests"
```

---

### Task 4: DOCX Package Skeleton and Zip Packaging

**Files:**
- Create: `Sources/iMessagePrinter/Services/Export/DocxWriter.swift`
- Create: `Sources/iMessagePrinter/Services/Export/DocxPackage.swift`
- Create: `Sources/iMessagePrinter/Services/Export/ZipPackager.swift`
- Create: `Tests/iMessagePrinterTests/DocxPackageTests.swift`

**Interfaces:**
- Produces: `enum DocxWriter { static func contentTypesXML(hasImages: Bool) -> String; static func rootRelationshipsXML() -> String; static func documentRelationshipsXML(imageFileNames: [String]) -> String; static func stylesXML() -> String; static func footerXML(conversationName: String) -> String; static func corePropertiesXML(title: String, createdAt: Date) -> String; static func appPropertiesXML() -> String }`
- Produces: `struct DocxPackage { var files: [String: Data]; var media: [String: URL]; func write(stagingDirectory: URL, to url: URL) throws }`
- Produces: `enum ZipPackager { static func zip(stagingDirectory: URL, outputURL: URL) throws }`
- Produces: `enum DocxError: LocalizedError { case zipFailed(Int32, String); case cannotCreatePackage }`

- [ ] **Step 1: Write the failing package test**

`Tests/iMessagePrinterTests/DocxPackageTests.swift`:

```swift
func testWritesAValidDocxPackage() throws {
    let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".docx")
    let staging = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: out)
        try? FileManager.default.removeItem(at: staging)
    }
    var files: [String: Data] = [
        "[Content_Types].xml": Data(DocxWriter.contentTypesXML(hasImages: false).utf8),
        "_rels/.rels": Data(DocxWriter.rootRelationshipsXML().utf8),
        "word/styles.xml": Data(DocxWriter.stylesXML().utf8),
        "word/footer1.xml": Data(DocxWriter.footerXML(conversationName: "Jane").utf8),
        "docProps/core.xml": Data(DocxWriter.corePropertiesXML(title: "Jane", createdAt: Date()).utf8),
        "docProps/app.xml": Data(DocxWriter.appPropertiesXML().utf8),
        "word/document.xml": Data("<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body><w:p><w:r><w:t>Hello &amp; goodbye</w:t></w:r></w:p></w:body></w:document>".utf8),
        "word/_rels/document.xml.rels": Data(DocxWriter.documentRelationshipsXML(imageFileNames: []).utf8)
    ]
    try DocxPackage(files: files, media: [:]).write(stagingDirectory: staging, to: out)
    try assertValidZip(out)
    let text = try textutilText(out)
    XCTAssertTrue(text.contains("Hello & goodbye"))
    let styles = try zipFileText(out, path: "word/styles.xml")
    XCTAssertTrue(styles.contains("Heading1"))
    XCTAssertTrue(styles.contains("Heading2"))
    XCTAssertTrue(styles.contains("MessageBody"))
}
```

Add `assertValidZip(_:)`, `textutilText(_:)`, and `zipFileText(_:path:)` to `TestSupport.swift`. Use `Process` with `/usr/bin/unzip -t`, `/usr/bin/textutil -convert txt -stdout`, and `/usr/bin/unzip -p`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter DocxPackageTests`
Expected: compile failure, `DocxWriter` is not defined.

- [ ] **Step 3: Implement the package parts and zip helper**

Write the XML parts with the styles listed in the spec. `DocxPackage.write` creates the given staging directory if needed, writes `files` at their relative paths, copies each `media` source URL to its relative path, calls `ZipPackager`, removes an existing destination file, then moves the archive into place. It does not remove the staging directory; the caller owns cleanup. `ZipPackager` runs `/usr/bin/zip -X -q -r <temp.docx> . -x '.*'` with `currentDirectoryURL` set to the staging directory and throws with stderr on a non-zero exit.

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter DocxPackageTests`
Expected: pass; `unzip -t` reports no errors and `textutil` reads the text.

- [ ] **Step 5: Commit**

```bash
git add Sources/iMessagePrinter/Services/Export/DocxWriter.swift Sources/iMessagePrinter/Services/Export/DocxPackage.swift Sources/iMessagePrinter/Services/Export/ZipPackager.swift Tests/iMessagePrinterTests/DocxPackageTests.swift Tests/iMessagePrinterTests/TestSupport.swift
git commit -m "feat: add docx package writer and zip packaging"
```

---

### Task 5: DOCX Timeline Rendering

**Files:**
- Modify: `Sources/iMessagePrinter/Services/Export/DocxWriter.swift`
- Create: `Tests/iMessagePrinterTests/DocxTimelineTests.swift`

**Interfaces:**
- Produces: `DocxWriter.documentXML(conversation: ExportConversation, preparedImages: [Int64: PreparedImage], exportedAt: Date) -> String`
- Produces: `struct PreparedImage: Equatable { let fileName: String; let pixelWidth: Int; let pixelHeight: Int }`

- [ ] **Step 1: Write the failing timeline tests**

`Tests/iMessagePrinterTests/DocxTimelineTests.swift` builds a fixture conversation spanning January and February 2024 with two messages on one day and one on the next month. Assert:

```swift
let xml = DocxWriter.documentXML(conversation: conversation, preparedImages: [:], exportedAt: date)

XCTAssertEqual(xml.components(separatedBy: "w:val=\"Heading1\"").count - 1, 1)
XCTAssertTrue(xml.contains("w:val=\"Heading2\""))
XCTAssertTrue(xml.contains("January 2024"))
XCTAssertTrue(xml.contains("February 2024"))
XCTAssertTrue(xml.contains("DateSeparator"))
XCTAssertTrue(xml.contains("Hello &amp; goodbye"))
XCTAssertTrue(xml.contains("MessageBody"))
XCTAssertTrue(xml.contains("MessageMeta"))
XCTAssertTrue(xml.contains("❤️ Jane"))
XCTAssertTrue(xml.contains("attachment.pdf"))
XCTAssertTrue(xml.contains("Reply in thread"))
```

Add one assertion that a message containing `&`, `<`, `>`, newlines, and a tab renders escaped text, `<w:br/>`, and `<w:tab/>`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter DocxTimelineTests`
Expected: compile failure, `documentXML` is not defined.

- [ ] **Step 3: Implement the timeline XML**

Emit: cover paragraphs, page break before the Heading 1, one Heading 1 with the conversation name, a Heading 2 when the month changes, a DateSeparator when the day changes, then MessageMeta, MessageBody, Reaction, thread marker, attachment label, and image paragraphs. Use the exact style IDs from the spec. Skip messages whose `hasContent` is false. Use `XMLText.runs` for body text and `XMLText.escape` for single-line values. Build into one `String` with `reserveCapacity(conversation.messages.count * 400)`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter DocxTimelineTests`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/iMessagePrinter/Services/Export/DocxWriter.swift Tests/iMessagePrinterTests/DocxTimelineTests.swift
git commit -m "feat: render docx chronological timeline"
```

---

### Task 6: Image Preparation and Inline Images

**Files:**
- Create: `Sources/iMessagePrinter/Services/Export/ImagePreparer.swift`
- Modify: `Sources/iMessagePrinter/Services/Export/DocxWriter.swift`
- Create: `Tests/iMessagePrinterTests/DocxImageTests.swift`

**Interfaces:**
- Produces: `enum ImagePreparer { static func prepare(attachments: [ExportAttachment], mode: ExportImageMode, stagingDirectory: URL, onPrepared: @escaping (Int) -> Void, isCancelled: @escaping () -> Bool) -> [Int64: PreparedImage] }`
- Consumes: `DocxWriter.documentXML(conversation:preparedImages:exportedAt:)` from Task 5.

- [ ] **Step 1: Write the failing image tests**

`Tests/iMessagePrinterTests/DocxImageTests.swift` creates a 4×2 PNG at a temp path, makes an `ExportAttachment` pointing at it, and asserts:

```swift
let staging = try makeStagingDirectory()
let images = ImagePreparer.prepare(attachments: [attachment], mode: .thumbnail, stagingDirectory: staging, onPrepared: { _ in }, isCancelled: { false })
let prepared = try XCTUnwrap(images[attachment.id])
XCTAssertTrue(FileManager.default.fileExists(atPath: staging.appendingPathComponent("word/media/\(prepared.fileName)").path))
XCTAssertLessThanOrEqual(max(prepared.pixelWidth, prepared.pixelHeight), 640)

let xml = DocxWriter.documentXML(conversation: conversationWith(attachment), preparedImages: images, exportedAt: Date())
XCTAssertTrue(xml.contains("<w:drawing>"))
XCTAssertTrue(xml.contains("r:embed=\"rIdImage1\""))
```

Also test:
- `mode: .omit` returns an empty map.
- A missing path returns no entry and the XML contains the filename label.
- A full-resolution PNG keeps the original dimensions.
- A 4000×3000 generated image produces a thumbnail no larger than 640 px on its longest side.
- A corrupt file returns no entry and does not throw.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter DocxImageTests`
Expected: compile failure, `ImagePreparer` is not defined.

- [ ] **Step 3: Implement `ImagePreparer`**

Use `CGImageSourceCreateWithURL`. Read pixel dimensions from `CGImageSourceCopyPropertiesAtIndex`, swapping width/height for orientations 5-8. For full-resolution PNG/JPEG, copy the original bytes. For other formats, decode and write JPEG at 0.9. For thumbnails, use `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceCreateThumbnailFromImageAlways: true`, `kCGImageSourceCreateThumbnailWithTransform: true`, and `kCGImageSourceThumbnailMaxPixelSize: 640`, then write JPEG at 0.85. Return a map keyed by attachment id. Undecodable files return no entry.

- [ ] **Step 4: Add image paragraphs to `documentXML`**

For each attachment whose id is in `preparedImages`, emit a `<w:p>` containing `<w:drawing>` with `wp:inline`, `wp:extent`, `wp:docPr`, `a:graphic`, `pic:pic`, `a:blip r:embed="rIdImageN"`, and `a:ext`. Size in EMU from pixels at 96 DPI, capped at 4.5" wide and 6" tall. Sort prepared images by attachment id. Use that same order for the relationship ids and the drawing paragraphs, starting at 1.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter DocxImageTests`
Expected: pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/iMessagePrinter/Services/Export/ImagePreparer.swift Sources/iMessagePrinter/Services/Export/DocxWriter.swift Tests/iMessagePrinterTests/DocxImageTests.swift
git commit -m "feat: embed images in docx export"
```

---

### Task 7: DOCX Export Service

**Files:**
- Create: `Sources/iMessagePrinter/Services/Export/DocxExportService.swift`
- Create: `Tests/iMessagePrinterTests/DocxExportServiceTests.swift`

**Interfaces:**
- Produces: `enum DocxExportService { static func export(conversation: ExportConversation, imageMode: ExportImageMode, to url: URL, progress: @escaping (ExportProgress) -> Void, isCancelled: @escaping () -> Bool) throws }`

- [ ] **Step 1: Write the failing service tests**

`Tests/iMessagePrinterTests/DocxExportServiceTests.swift`:

```swift
func testExportsAValidDocxAndReportsProgress() throws {
    let fixture = makeConversationFixture(messageCount: 3, imageCount: 1)
    let out = tempDocx()
    var fractions: [Double] = []
    try DocxExportService.export(conversation: fixture, imageMode: .thumbnail, to: out, progress: { fractions.append($0.fraction) }, isCancelled: { false })
    try assertValidZip(out)
    XCTAssertTrue(try textutilText(out).contains("Hello"))
    XCTAssertEqual(fractions.last ?? 0, 1.0, accuracy: 0.001)
    XCTAssertTrue(fractions.count > 1)
}

func testCancellationLeavesNoDestinationFile() throws {
    let out = tempDocx()
    XCTAssertThrowsError(try DocxExportService.export(conversation: fixture, imageMode: .thumbnail, to: out, progress: { _ in }, isCancelled: { true }))
    XCTAssertFalse(FileManager.default.fileExists(atPath: out.path))
}

func testOmitModeAddsNoMedia() throws {
    let out = tempDocx()
    try DocxExportService.export(conversation: fixtureWithImage, imageMode: .omit, to: out, progress: { _ in }, isCancelled: { false })
    let listing = try zipListing(out)
    XCTAssertFalse(listing.contains("word/media/"))
    XCTAssertTrue(try textutilText(out).contains("IMG_0001"))
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter DocxExportServiceTests`
Expected: compile failure.

- [ ] **Step 3: Implement the service**

Create a UUID staging directory and remove it in a `defer`. Build an `ExportProgressEstimator` with `conversation.messages.count` and the count of exportable image attachments. An attachment is exportable when `isImage`, `resolvedPath != nil`, and the file exists; use the same predicate here, in `ImagePreparer`, and in the writer. Call `ImagePreparer` into `staging/word/media`. Build all package parts from `DocxWriter` using the sorted prepared images for `contentTypesXML(hasImages:)`, `documentRelationshipsXML(imageFileNames:)`, and `documentXML`. The media files are already in staging, so pass `media: [:]` to `DocxPackage`; call `DocxPackage(...).write(stagingDirectory: staging, to: url)`, which handles the temp archive. Emit progress for `.preparing`, `.images`, `.rendering`, `.compressing`, and `.finishing`. On cancel or error, remove any temp output, then rethrow. Report `fraction = 1.0` before returning.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter DocxExportServiceTests`
Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/iMessagePrinter/Services/Export/DocxExportService.swift Tests/iMessagePrinterTests/DocxExportServiceTests.swift
git commit -m "feat: add docx export service"
```

---

### Task 8: Move PDF onto the Shared Export Pipeline

**Files:**
- Modify: `Sources/iMessagePrinter/Services/PDFExportService.swift`
- Modify: `Sources/iMessagePrinter/Views/ExportAccessoryView.swift`
- Create: `Tests/iMessagePrinterTests/PDFExportServiceTests.swift`

**Interfaces:**
- Produces: `PDFExportService.export(conversation: ExportConversation, imageMode: ExportImageMode, to url: URL, progress: @escaping (ExportProgress) -> Void, isCancelled: @escaping () -> Bool) throws`
- Consumes: `ExportConversation`, `ExportMessage`, `ExportImageMode`.

- [ ] **Step 1: Write the failing PDF regression test**

`Tests/iMessagePrinterTests/PDFExportServiceTests.swift` builds a two-message `ExportConversation`, exports to a temp PDF, then:

```swift
import PDFKit
let doc = try XCTUnwrap(PDFDocument(url: out))
XCTAssertGreaterThanOrEqual(doc.pageCount, 1)
XCTAssertTrue((doc.string ?? "").contains("Hello"))
```

Add a cancel test that asserts no file remains.

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter PDFExportServiceTests`
Expected: compile failure, the new signature does not exist.

- [ ] **Step 3: Adapt the PDF service**

Replace `PDFExportService.AttachmentMode` with `ExportImageMode`, and change `ExportAccessoryView.selectedMode` to return `ExportImageMode`. Add the new `export(conversation:imageMode:to:progress:isCancelled:)` signature and move the existing drawing code onto `conversation.messages`. All image drawing already uses `att.resolvedPath` and `NSImage(contentsOfFile:)`, so no image model change is needed. Add `isCancelled()` checks at the top of each message loop and `progress` updates through an `ExportProgressEstimator`.

Keep the old `export(conversation:messages:attachmentMode:to:)` overload as a thin adapter so `AppState.exportPDF()` still compiles until Task 9. Map each `DisplayMessage` to `ExportMessage` and call the new function with no-op progress and cancellation. Keep `typealias AttachmentMode = ExportImageMode` until Task 9 removes the old path.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter PDFExportServiceTests`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/iMessagePrinter/Services/PDFExportService.swift Sources/iMessagePrinter/Views/ExportAccessoryView.swift Tests/iMessagePrinterTests/PDFExportServiceTests.swift
git commit -m "refactor: share export data pipeline with PDF"
```

---

### Task 9: Modal Export Session and Menu

**Files:**
- Create: `Sources/iMessagePrinter/Services/Export/ExportCoordinator.swift`
- Create: `Sources/iMessagePrinter/Views/ExportProgressPanel.swift`
- Modify: `Sources/iMessagePrinter/App/AppState.swift`
- Modify: `Sources/iMessagePrinter/Views/MessageDetailView.swift`
- Modify: `Sources/iMessagePrinter/Views/ConversationListView.swift`
- Create: `Tests/iMessagePrinterTests/ExportCoordinatorTests.swift`

**Interfaces:**
- Produces: `final class ExportCoordinator { func begin() -> Bool; func end() }`
- Produces: `AppState.export(_ format: ExportFormat)`
- Produces: `final class ExportProgressPanel: NSPanel { var onCancel: (() -> Void)?; init(format: ExportFormat, conversationName: String); func update(_ progress: ExportProgress); func setStatus(_ text: String); func finish() }`

- [ ] **Step 1: Write the failing coordinator test**

`Tests/iMessagePrinterTests/ExportCoordinatorTests.swift`:

```swift
func testOnlyOneExportCanBegin() {
    let c = ExportCoordinator()
    XCTAssertTrue(c.begin())
    XCTAssertFalse(c.begin())
    c.end()
    XCTAssertTrue(c.begin())
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter ExportCoordinatorTests`
Expected: compile failure.

- [ ] **Step 3: Implement the coordinator, panel, and AppState flow**

`ExportCoordinator` is a small `NSLock`-guarded boolean. `AppState` owns one and exposes `isExporting`.

`AppState.export(_ format:)`:
1. Guard `!isExporting`, a selected conversation, and non-empty messages.
2. Present `NSSavePanel` with `ExportAccessoryView`; set `.pdf` or `.docx` content type and a filename using `format.defaultNameSuffix`.
3. Capture `conversation`, `imageMode`, `url`, and the database/handle map.
4. `guard coordinator.begin() else { return }`; set `isExporting = true`.
5. Create `ExportProgressPanel`, a `CancelFlag`, and a task. Start the task from `DispatchQueue.main.async` so it begins after the modal loop starts, then call `NSApp.runModal(for: panel)`.
6. The task plans the conversation with `ExportPlanner`, then calls `PDFExportService` or `DocxExportService`. Progress callbacks update the panel on the main thread.
7. On completion or cancellation, call `panel.finish()`, `NSApp.stopModal()`, `coordinator.end()`, `isExporting = false`, and open the destination only on success.

`MessageDetailView` replaces the PDF button with an `Export` menu containing `Export PDF…` and `Export Word Document…`. Remove the old `isExportingPDF` overlay; the modal panel owns progress. Keep the menu disabled while loading or exporting. Update `ConversationListView` to use `isExporting`.

Remove the old `PDFExportService.export(conversation:messages:attachmentMode:to:)` adapter and the `AttachmentMode` typealias. `AppState` now calls only the new signatures.

- [ ] **Step 4: Run the coordinator test and build**

Run: `swift test --filter ExportCoordinatorTests`
Expected: pass.
Run: `swift build`
Expected: succeeds.

- [ ] **Step 5: Manual check**

Run: `make dev`, select a conversation, start a Word export and a PDF export. Confirm the panel is modal, progress moves, Cancel stops it, a second export cannot start, and the `.docx` opens in Pages.

- [ ] **Step 6: Commit**

```bash
git add Sources/iMessagePrinter/Services/Export/ExportCoordinator.swift Sources/iMessagePrinter/Views/ExportProgressPanel.swift Sources/iMessagePrinter/App/AppState.swift Sources/iMessagePrinter/Views/MessageDetailView.swift Sources/iMessagePrinter/Views/ConversationListView.swift Tests/iMessagePrinterTests/ExportCoordinatorTests.swift
git commit -m "feat: make exports modal with progress and cancel"
```

---

### Task 10: Baseline Benchmark

**Files:**
- Create: `Tests/iMessagePrinterTests/DocxBenchmarkTests.swift`
- Create: `docs/superpowers/benchmarks/2026-11-24-docx.md`

**Interfaces:**
- Consumes: `DatabaseService`, `ExportPlanner`, `DocxExportService`.

Add test helpers `conversationInfo(_ raw: RawConversation, db: DatabaseService) throws -> ConversationInfo`, `plan(_ conversation: ConversationInfo, mode: ExportImageMode, db: DatabaseService) throws -> ExportConversation`, and `tempDocx(_ label: String) -> URL` in the benchmark test file.

- [ ] **Step 1: Write the gated benchmark test**

```swift
func testBenchmarkLargestConversation() throws {
    guard ProcessInfo.processInfo.environment["IMESSAGEPRINTER_BENCHMARK"] == "1" else {
        throw XCTSkip("Set IMESSAGEPRINTER_BENCHMARK=1 to run")
    }
    let db = try DatabaseService()
    let raw = try XCTUnwrap(try db.fetchConversations().max { $0.messageCount < $1.messageCount })
    let conversation = try conversationInfo(raw, db: db)
    for mode in [ExportImageMode.omit, .thumbnail, .fullResolution] {
        let out = tempDocx("bench-\(mode.rawValue)")
        let start = Date()
        try DocxExportService.export(conversation: try plan(conversation, mode: mode, db: db), imageMode: mode, to: out, progress: { _ in }, isCancelled: { false })
        let seconds = Date().timeIntervalSince(start)
        let bytes = try FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int64 ?? 0
        print("BENCH mode=\(mode.rawValue) seconds=\(seconds) bytes=\(bytes) msgs=\(conversation.messageCount)")
    }
}
```

- [ ] **Step 2: Run the baseline**

Run: `IMESSAGEPRINTER_BENCHMARK=1 swift test --filter DocxBenchmarkTests`
Expected: prints three `BENCH` lines against the real database.

- [ ] **Step 3: Record the numbers**

Write the command, machine, message count, image count, mode, seconds, and output size to `docs/superpowers/benchmarks/2026-11-24-docx.md`. State that this is the first correct implementation, before optimization.

- [ ] **Step 4: Commit**

```bash
git add Tests/iMessagePrinterTests/DocxBenchmarkTests.swift docs/superpowers/benchmarks/2026-11-24-docx.md
git commit -m "test: add docx export benchmark baseline"
```

---

### Task 11: Speed Up Word Export

**Files:**
- Modify: `Sources/iMessagePrinter/Services/DatabaseService.swift`
- Modify: `Sources/iMessagePrinter/Services/Export/ExportPlanner.swift`
- Modify: `Sources/iMessagePrinter/Services/Export/ImagePreparer.swift`
- Modify: `Sources/iMessagePrinter/Services/Export/ZipPackager.swift`
- Modify: `Tests/iMessagePrinterTests/ExportPlannerTests.swift`
- Modify: `Tests/iMessagePrinterTests/DocxImageTests.swift`
- Modify: `docs/superpowers/benchmarks/2026-11-24-docx.md`

**Interfaces:**
- Produces: `DatabaseService.fetchAttachments(chatRowID: Int64) throws -> [Int64: [AttachmentRecord]]`
- Changes internally: `ImagePreparer.prepare` runs image work in parallel; `ZipPackager` stores entries with `-0`.

- [ ] **Step 1: Add a failing bulk-attachment test**

In `ExportPlannerTests`, assert that a chat with two attachments on two different messages returns both through the planner, and that an attachment from another chat is absent.

- [ ] **Step 2: Implement the bulk fetch**

Add `messageID` to `AttachmentRecord` as an optional field mapped from `maj.message_id AS message_id`. Add `fetchAttachments(chatRowID:)` with one join query over `chat_message_join`, `message_attachment_join`, and `attachment`. Update `ExportPlanner` to call it once per conversation and group by message id.

- [ ] **Step 3: Run the planner tests**

Run: `swift test --filter ExportPlannerTests`
Expected: pass.

- [ ] **Step 4: Parallelize image preparation**

Replace the sequential loop with `DispatchQueue.concurrentPerform(iterations: attachments.count)`. Each worker writes to its own media path. Protect the result dictionary and progress counter with an `NSLock`. Skip work when `isCancelled()` is true. Keep output file names assigned deterministically by attachment index before the parallel loop.

- [ ] **Step 5: Store zip entries uncompressed**

Change `ZipPackager` to `zip -X -q -0 -r ...`. Run `DocxPackageTests` and `DocxExportServiceTests` to confirm the packages still open.

- [ ] **Step 6: Re-run the benchmark**

Run: `IMESSAGEPRINTER_BENCHMARK=1 swift test --filter DocxBenchmarkTests`
Expected: three new `BENCH` lines.

- [ ] **Step 7: Record the after numbers**

Append a second table to `docs/superpowers/benchmarks/2026-11-24-docx.md` with the same columns. State the speedup per mode.

- [ ] **Step 8: Commit**

```bash
git add Sources/iMessagePrinter/Services/DatabaseService.swift Sources/iMessagePrinter/Services/Export/ExportPlanner.swift Sources/iMessagePrinter/Services/Export/ImagePreparer.swift Sources/iMessagePrinter/Services/Export/ZipPackager.swift Tests/iMessagePrinterTests/ExportPlannerTests.swift Tests/iMessagePrinterTests/DocxImageTests.swift docs/superpowers/benchmarks/2026-11-24-docx.md
git commit -m "perf: bulk-fetch attachments, parallelize images, store media"
```

- [ ] **Step 9: Run the full suite**

Run: `swift test`
Expected: all tests pass.

---

### Task 12: Full Verification and Documentation

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/benchmarks/2026-11-24-docx.md` if final numbers change.

- [ ] **Step 1: Run the full suite**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 2: Build release**

Run: `swift build --configuration release`
Expected: succeeds.

- [ ] **Step 3: Manual acceptance on a real conversation**

Run: `make run`.
- Export a conversation with several thousand messages and images to Word.
- Open the result in Pages and `textutil -convert txt`.
- Confirm one timeline, month headings, editable/searchable text, highlights, images, and page numbers.
- Start a second export mid-run and confirm it is blocked.
- Change the selected conversation mid-export and confirm the output still contains the original.
- Cancel and confirm no destination file remains.

- [ ] **Step 4: Update README**

Add the Word export option, the modal progress behavior, and a note that both formats export the selected conversation. Include the benchmark summary.

- [ ] **Step 5: Commit**

```bash
git add README.md docs/superpowers/benchmarks/2026-11-24-docx.md
git commit -m "docs: document Word export and benchmark results"
```
