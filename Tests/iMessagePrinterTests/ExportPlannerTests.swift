import XCTest
@testable import iMessagePrinter

final class ExportPlannerTests: XCTestCase {
    func testPlansOnlyTheSelectedChat() throws {
        let fixture = try makeFixture()
        let plan = try planChat1(fixture)
        XCTAssertEqual(plan.messages.map(\.id), [1, 2, 3])
        XCTAssertFalse(plan.messages.contains { $0.id == 4 })
    }

    func testAttachesReactionsToTheTargetMessage() throws {
        let plan = try planChat1(try makeFixture())
        let target = try XCTUnwrap(plan.messages.first { $0.id == 1 })
        XCTAssertEqual(target.reactions.count, 1)
        XCTAssertEqual(target.reactions.first?.emoji, "\u{2764}\u{FE0F}")
    }

    func testParsesAttributedBodyWhenTextIsNil() throws {
        let plan = try planChat1(try makeFixture())
        let message = try XCTUnwrap(plan.messages.first { $0.id == 3 })
        XCTAssertEqual(message.text, fixtureTypedStreamText)
    }

    func testReportsMessagesWithAttachments() throws {
        let plan = try planChat1(try makeFixture())
        let message = try XCTUnwrap(plan.messages.first { $0.id == 2 })
        XCTAssertEqual(message.attachments.count, 1)
        XCTAssertEqual(message.attachments.first?.id, 1)
    }

    func testSnapshotIgnoresLaterDatabaseChanges() throws {
        let fixture = try makeFixture()
        let plan = try planChat1(fixture)
        try fixture.executeSQL("UPDATE message SET text = 'changed' WHERE ROWID = 1")
        XCTAssertEqual(plan.messages.first?.text, "original")
    }
}
