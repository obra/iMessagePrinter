import PDFKit
import XCTest
@testable import iMessagePrinter

final class PDFExportServiceTests: XCTestCase {
    func testExportsPDFFromExportConversation() throws {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: out) }

        try PDFExportService.export(
            conversation: makePDFConversation(),
            imageMode: .omit,
            to: out,
            progress: { _ in },
            isCancelled: { false }
        )

        let document = try XCTUnwrap(PDFDocument(url: out))
        XCTAssertGreaterThanOrEqual(document.pageCount, 1)
        XCTAssertTrue((document.string ?? "").contains("Hello"))

        let text = document.string ?? ""
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for date in [base, base.addingTimeInterval(60)] {
            let stamp = DateFormatting.formatMessageTimestamp(date)
            let parts = stamp.split(separator: " ", maxSplits: 1).map(String.init)
            XCTAssertTrue(text.contains(parts[0]), "PDF is missing the message date \(parts[0])")
            XCTAssertTrue(text.contains(parts[1]), "PDF is missing the message time \(parts[1])")
        }
    }

    func testCancellationLeavesNoFile() throws {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: out) }

        XCTAssertThrowsError(try PDFExportService.export(
            conversation: makePDFConversation(),
            imageMode: .omit,
            to: out,
            progress: { _ in },
            isCancelled: { true }
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.path))
    }
}

private func makePDFConversation() -> ExportConversation {
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    return ExportConversation(
        chatRowID: 1,
        chatGUID: "chat-1",
        displayName: "Jane",
        participants: ["+15551234567"],
        participantNames: ["Jane"],
        serviceName: "iMessage",
        isGroupChat: false,
        messages: [
            ExportMessage(
                id: 1,
                guid: "m1",
                text: "Hello from PDF",
                senderName: "Jane",
                senderID: "+15551234567",
                isFromMe: false,
                date: base,
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
                attachments: []
            ),
            ExportMessage(
                id: 2,
                guid: "m2",
                text: "Second message",
                senderName: "Me",
                senderID: "Me",
                isFromMe: true,
                date: base.addingTimeInterval(60),
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
                attachments: []
            ),
        ]
    )
}
