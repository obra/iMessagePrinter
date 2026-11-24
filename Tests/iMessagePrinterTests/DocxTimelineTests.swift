import XCTest
@testable import iMessagePrinter

final class DocxTimelineTests: XCTestCase {
    func testRendersChronologicalTimelineStructure() throws {
        let conversation = makeTimelineConversation()
        let xml = DocxWriter.documentXML(
            conversation: conversation,
            preparedImages: [:],
            exportedAt: makeDate(2024, 2, 10, 12)
        )

        XCTAssertEqual(xml.components(separatedBy: "w:val=\"Heading1\"").count - 1, 1)
        XCTAssertTrue(xml.contains("w:val=\"Heading2\""))
        XCTAssertTrue(xml.contains("January 2024"))
        XCTAssertTrue(xml.contains("February 2024"))
        XCTAssertTrue(xml.contains("DateSeparator"))
        XCTAssertTrue(xml.contains("Hello &amp; goodbye"))
        XCTAssertTrue(xml.contains("MessageBody"))
        XCTAssertTrue(xml.contains("MessageMeta"))
        XCTAssertTrue(xml.contains("\u{2764}\u{FE0F} Jane"))
        XCTAssertTrue(xml.contains("attachment.pdf"))
        XCTAssertTrue(xml.contains("Reply in thread"))
    }

    func testEscapesBodyTextAndKeepsLineBreaksAndTabs() throws {
        let xml = DocxWriter.documentXML(
            conversation: makeTimelineConversation(),
            preparedImages: [:],
            exportedAt: makeDate(2024, 2, 10, 12)
        )

        XCTAssertTrue(xml.contains("a &amp; b &lt; c &gt; d"))
        XCTAssertTrue(xml.contains("<w:br/>"))
        XCTAssertTrue(xml.contains("<w:tab/>"))
    }
}

private func makeTimelineConversation() -> ExportConversation {
    let attachment = ExportAttachment(
        id: 1,
        filename: "/tmp/attachment.pdf",
        transferName: "attachment.pdf",
        mimeType: "application/pdf",
        totalBytes: 2048,
        isImage: false,
        resolvedPath: "/tmp/attachment.pdf",
        formattedSize: "2 KB"
    )

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
                text: "Hello & goodbye",
                senderName: "Jane",
                senderID: "+15551234567",
                isFromMe: false,
                date: makeDate(2024, 1, 15, 12),
                dateRead: nil,
                dateDelivered: nil,
                service: "iMessage",
                isDelivered: true,
                isRead: true,
                isSent: true,
                isSystemMessage: false,
                isEdited: false,
                isRetracted: false,
                replyToGUID: "m0",
                threadOriginatorGUID: "m0",
                groupTitle: nil,
                groupActionType: 0,
                reactions: [Reaction(emoji: "\u{2764}\u{FE0F}", senderName: "Jane")],
                attachments: [attachment]
            ),
            ExportMessage(
                id: 2,
                guid: "m2",
                text: "a & b < c > d\nsecond line\tend",
                senderName: "Me",
                senderID: "Me",
                isFromMe: true,
                date: makeDate(2024, 1, 15, 13),
                dateRead: nil,
                dateDelivered: nil,
                service: "iMessage",
                isDelivered: true,
                isRead: true,
                isSent: true,
                isSystemMessage: false,
                isEdited: true,
                isRetracted: false,
                replyToGUID: nil,
                threadOriginatorGUID: nil,
                groupTitle: nil,
                groupActionType: 0,
                reactions: [],
                attachments: []
            ),
            ExportMessage(
                id: 3,
                guid: "m3",
                text: "Second month",
                senderName: "Jane",
                senderID: "+15551234567",
                isFromMe: false,
                date: makeDate(2024, 2, 2, 12),
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

private func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.date(from: components)!
}
