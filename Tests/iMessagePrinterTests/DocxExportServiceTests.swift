import XCTest
@testable import iMessagePrinter

final class DocxExportServiceTests: XCTestCase {
    func testExportsAValidDocxAndReportsProgress() throws {
        let conversation = try makeConversationFixture(messageCount: 3, imageCount: 1)
        let out = tempDocx()
        defer { try? FileManager.default.removeItem(at: out) }
        var fractions: [Double] = []

        try DocxExportService.export(
            conversation: conversation,
            imageMode: .thumbnail,
            to: out,
            progress: { fractions.append($0.fraction) },
            isCancelled: { false }
        )

        try assertValidZip(out)
        try assertWellFormedXMLParts(out)
        XCTAssertTrue(try textutilText(out).contains("Hello"))
        XCTAssertEqual(fractions.last ?? 0, 1.0, accuracy: 0.001)
        XCTAssertTrue(fractions.count > 1)
    }

    func testCancellationLeavesNoDestinationFile() throws {
        let conversation = try makeConversationFixture(messageCount: 3, imageCount: 1)
        let out = tempDocx()
        defer { try? FileManager.default.removeItem(at: out) }

        XCTAssertThrowsError(try DocxExportService.export(
            conversation: conversation,
            imageMode: .thumbnail,
            to: out,
            progress: { _ in },
            isCancelled: { true }
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.path))
    }

    func testOmitModeAddsNoMedia() throws {
        let conversation = try makeConversationFixture(messageCount: 3, imageCount: 1)
        let out = tempDocx()
        defer { try? FileManager.default.removeItem(at: out) }

        try DocxExportService.export(
            conversation: conversation,
            imageMode: .omit,
            to: out,
            progress: { _ in },
            isCancelled: { false }
        )

        let listing = try zipListing(out)
        XCTAssertFalse(listing.contains("word/media/"))
        XCTAssertTrue(try textutilText(out).contains("IMG_0001"))
    }
}
