import AppKit
import Foundation
import ImageIO
import XCTest
@testable import iMessagePrinter

final class ReviewFixTests: XCTestCase {
    // MARK: - Destination durability

    func testDocxPackagingFailurePreservesExistingDestination() throws {
        let out = tempDocx()
        let original = Data("ORIGINAL DOCX".utf8)
        try original.write(to: out)
        defer { try? FileManager.default.removeItem(at: out) }

        let conversation = try makeConversationFixture(messageCount: 2, imageCount: 0)

        XCTAssertThrowsError(try DocxExportService.export(
            conversation: conversation,
            imageMode: .omit,
            to: out,
            progress: { _ in },
            isCancelled: { false },
            writePackage: { _, _, _ in throw ReviewFixtureError.packagingFailed }
        ))
        XCTAssertEqual(try Data(contentsOf: out), original)
    }

    func testDocxCancellationBeforePublicationPreservesExistingDestination() throws {
        let out = tempDocx()
        let original = Data("ORIGINAL DOCX".utf8)
        try original.write(to: out)
        defer { try? FileManager.default.removeItem(at: out) }

        let conversation = try makeConversationFixture(messageCount: 4, imageCount: 0)
        var sawCompressing = false

        XCTAssertThrowsError(try DocxExportService.export(
            conversation: conversation,
            imageMode: .omit,
            to: out,
            progress: { if $0.phase == .compressing { sawCompressing = true } },
            isCancelled: { sawCompressing }
        ))
        XCTAssertTrue(sawCompressing, "the export must reach the packaging phase before the cancel check")
        XCTAssertEqual(try Data(contentsOf: out), original)
    }

    func testDocxCancellationDuringRenderingStopsExport() throws {
        let out = tempDocx()
        let original = Data("ORIGINAL DOCX".utf8)
        try original.write(to: out)
        defer { try? FileManager.default.removeItem(at: out) }

        let conversation = makeReviewConversation(
            texts: (0..<800).map { "Message \($0)" }
        )
        var cancelRendering = false

        XCTAssertThrowsError(try DocxExportService.export(
            conversation: conversation,
            imageMode: .omit,
            to: out,
            progress: { progress in
                if progress.phase == .rendering {
                    cancelRendering = true
                }
            },
            isCancelled: { cancelRendering }
        )) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(try Data(contentsOf: out), original)
    }

    func testPDFLateCancellationPreservesExistingDestination() throws {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).pdf")
        let original = Data("ORIGINAL PDF".utf8)
        try original.write(to: out)
        defer { try? FileManager.default.removeItem(at: out) }

        let conversation = makeReviewConversation(
            texts: (0..<30).map { "Message \($0)" }
        )
        var cancelAtEnd = false

        XCTAssertThrowsError(try PDFExportService.export(
            conversation: conversation,
            imageMode: .omit,
            to: out,
            progress: { progress in
                if progress.processedMessages == progress.totalMessages {
                    cancelAtEnd = true
                }
            },
            isCancelled: { cancelAtEnd }
        )) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(try Data(contentsOf: out), original)
    }

    // MARK: - WordprocessingML validity

    func testStylesEmitSpacingBeforeOutlineLevel() throws {
        let styles = DocxWriter.stylesXML()
        for styleID in ["Heading1", "Heading2"] {
            let styleStart = try XCTUnwrap(styles.range(of: "w:styleId=\"\(styleID)\"")?.lowerBound)
            let styleEnd = try XCTUnwrap(styles.range(of: "</w:style>", range: styleStart..<styles.endIndex)?.lowerBound)
            let style = styles[styleStart..<styleEnd]
            let spacing = try XCTUnwrap(style.range(of: "<w:spacing"))
            let outline = try XCTUnwrap(style.range(of: "<w:outlineLvl"))
            XCTAssertLessThan(spacing.lowerBound, outline.lowerBound)
        }
    }

    func testCombiningMarkAfterNewlineStaysOutOfRunMarkup() throws {
        let conversation = makeReviewConversation(texts: ["first\n\u{0301}second"])
        let xml = try DocxWriter.documentXML(
            conversation: conversation,
            preparedImages: [:],
            exportedAt: Date()
        )
        XCTAssertTrue(xml.contains("<w:br/><w:t xml:space=\"preserve\">\u{0301}second</w:t>"))
        XCTAssertFalse(xml.contains("<w:t xml:space=\"preserve\"><w:br"))
    }

    func testEscapeDropsXMLInvalidScalars() {
        XCTAssertEqual(XMLText.escape("\u{FFFE}\u{FFFF}ok"), "ok")
    }

    func testRepeatedAttachmentPlacementUsesUniqueDrawingIDs() throws {
        let path = try makeTestPNG(width: 8, height: 6)
        let attachment = ExportAttachment(
            id: 42,
            filename: path.path,
            transferName: "repeated.png",
            mimeType: "image/png",
            totalBytes: 200,
            isImage: true,
            resolvedPath: path.path,
            formattedSize: "200 bytes"
        )
        let conversation = makeReviewConversation(
            texts: ["with image", "same image again"],
            attachments: [[attachment], [attachment]]
        )
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("review-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        var preparedCalls = 0

        let images = ImagePreparer.prepare(
            attachments: conversation.messages.flatMap { $0.attachments },
            mode: .thumbnail,
            stagingDirectory: staging,
            onPrepared: { _ in preparedCalls += 1 },
            isCancelled: { false }
        )
        XCTAssertEqual(preparedCalls, 1)
        XCTAssertEqual(images.count, 1)

        let xml = try DocxWriter.documentXML(
            conversation: conversation,
            preparedImages: images,
            exportedAt: Date()
        )
        let ids = docPrIDs(in: xml)
        XCTAssertEqual(ids.count, 2)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testTruncatedPNGIsNotEmbeddedAtFullResolution() throws {
        let valid = try makeTestPNG(width: 40, height: 20)
        let bytes = try Data(contentsOf: valid)
        let truncated = FileManager.default.temporaryDirectory
            .appendingPathComponent("truncated-\(UUID().uuidString).png")
        try bytes.prefix(33).write(to: truncated)
        defer { try? FileManager.default.removeItem(at: truncated) }

        let attachment = ExportAttachment(
            id: 7,
            filename: truncated.path,
            transferName: "broken.png",
            mimeType: "image/png",
            totalBytes: Int64(bytes.prefix(33).count),
            isImage: true,
            resolvedPath: truncated.path,
            formattedSize: "33 bytes"
        )
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("review-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        let images = ImagePreparer.prepare(
            attachments: [attachment],
            mode: .fullResolution,
            stagingDirectory: staging,
            onPrepared: { _ in },
            isCancelled: { false }
        )
        XCTAssertNil(images[attachment.id], "undecodable originals must fall back to a label, not embed garbage")
    }

    // MARK: - Progress

    func testDocxProgressIsMonotonicAndAdvancesDuringRendering() throws {
        let conversation = try makeConversationFixture(messageCount: 1_000, imageCount: 0)
        let out = tempDocx()
        defer { try? FileManager.default.removeItem(at: out) }
        var fractions: [(ExportProgress.Phase, Double)] = []

        try DocxExportService.export(
            conversation: conversation,
            imageMode: .omit,
            to: out,
            progress: { fractions.append(($0.phase, $0.fraction)) },
            isCancelled: { false }
        )

        let values = fractions.map(\.1)
        XCTAssertGreaterThanOrEqual(values.first ?? 0, 0.1 - 0.0001)
        for (earlier, later) in zip(values, values.dropFirst()) {
            XCTAssertLessThanOrEqual(earlier, later + 0.0001)
        }
        let rendering = fractions.filter { $0.0 == .rendering }.map(\.1)
        XCTAssertGreaterThan(rendering.count, 1, "rendering must report progress in batches")
    }

    func testPlannerProgressStaysWithinPreparingRange() throws {
        let fixture = try makeFixture()
        var fractions: [Double] = []
        _ = try ExportPlanner(
            db: fixture.db,
            handleMap: fixture.db.fetchAllHandles(),
            contactResolver: ContactResolver()
        ).plan(
            conversation: fixtureConversation(fixture, chatRowID: 1),
            imageMode: .omit,
            progress: { fractions.append($0.fraction) },
            isCancelled: { false }
        )
        XCTAssertFalse(fractions.isEmpty)
        XCTAssertLessThanOrEqual(fractions.max() ?? 1, 0.1 + 0.0001)
    }

    // MARK: - Modal helpers

    func testProgressRelayDeliversProgressAndOutcomeOnce() {
        let relay = ExportProgressRelay()
        let progress = ExportProgress(
            phase: .rendering,
            fraction: 0.4,
            processedMessages: 4,
            totalMessages: 10,
            processedImages: 0,
            totalImages: 0,
            estimatedRemaining: nil
        )
        relay.update(progress)
        relay.finish(.success(()))

        let first = relay.take()
        XCTAssertEqual(first.progress?.fraction, 0.4)
        XCTAssertNotNil(first.outcome)
        let second = relay.take()
        XCTAssertNil(second.progress)
        XCTAssertNil(second.outcome)
    }

    func testProgressPanelHidesWhenFinished() {
        _ = NSApplication.shared
        let panel = ExportProgressPanel(format: .docx, conversationName: "Jane")
        panel.orderFront(nil)
        XCTAssertTrue(panel.isVisible)
        panel.finish()
        XCTAssertFalse(panel.isVisible)
        panel.orderOut(nil)
    }

    func testContactResolverIsSafeUnderConcurrentLookup() {
        let resolver = ContactResolver()
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "contact-resolver", attributes: .concurrent)
        let results = NSMutableArray()
        let lock = NSLock()

        for index in 0..<8 {
            group.enter()
            queue.async {
                defer { group.leave() }
                for offset in 0..<500 {
                    let identifier = "+1555\(index)\(offset)"
                    let name = resolver.displayName(for: identifier)
                    lock.lock()
                    results.add(name)
                    lock.unlock()
                }
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 20), .success)
        XCTAssertEqual(results.count, 4_000)
    }
}

private enum ReviewFixtureError: Error {
    case packagingFailed
}

private func docPrIDs(in xml: String) -> [String] {
    let regex = try! NSRegularExpression(pattern: #"<wp:docPr id="([^"]+)""#)
    let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
    return regex.matches(in: xml, range: range).compactMap { match in
        guard let range = Range(match.range(at: 1), in: xml) else { return nil }
        return String(xml[range])
    }
}

private func makeReviewConversation(
    texts: [String],
    attachments: [[ExportAttachment]] = []
) -> ExportConversation {
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    let messages = texts.enumerated().map { index, text in
        ExportMessage(
            id: Int64(index + 1),
            guid: "review-\(index)",
            text: text,
            senderName: "Jane",
            senderID: "+15551234567",
            isFromMe: false,
            date: base.addingTimeInterval(Double(index) * 60),
            dateRead: nil,
            dateDelivered: nil,
            service: "iMessage",
            isDelivered: true,
            isRead: true,
            isSent: true,
            isSystemMessage: false,
            isEdited: false,
            isRetracted: false,
            replyToGUID: nil,
            threadOriginatorGUID: nil,
            groupTitle: nil,
            groupActionType: 0,
            reactions: [],
            attachments: index < attachments.count ? attachments[index] : []
        )
    }
    return ExportConversation(
        chatRowID: 1,
        chatGUID: "chat-1",
        displayName: "Jane",
        participants: ["+15551234567"],
        participantNames: ["Jane"],
        serviceName: "iMessage",
        isGroupChat: false,
        messages: messages
    )
}
