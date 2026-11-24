import XCTest
@testable import iMessagePrinter

final class DocxBenchmarkTests: XCTestCase {
    func testBenchmarkLargestConversation() throws {
        guard ProcessInfo.processInfo.environment["IMESSAGEPRINTER_BENCHMARK"] == "1" else {
            throw XCTSkip("Set IMESSAGEPRINTER_BENCHMARK=1 to run")
        }
        let db = try DatabaseService()
        let raw = try XCTUnwrap(try db.fetchConversations().max { $0.messageCount < $1.messageCount })
        let conversation = try conversationInfo(raw, db: db)

        for mode in [ExportImageMode.omit, .thumbnail, .fullResolution] {
            let out = tempDocx("bench-\(mode.rawValue)")
            defer { try? FileManager.default.removeItem(at: out) }

            let planned = try plan(conversation, mode: mode, db: db)
            let imageCount = planned.messages
                .flatMap(\.attachments)
                .filter { attachment in
                    guard attachment.isImage, let path = attachment.resolvedPath else { return false }
                    return FileManager.default.fileExists(atPath: path)
                }
                .count
            let start = Date()
            try DocxExportService.export(
                conversation: planned,
                imageMode: mode,
                to: out,
                progress: { _ in },
                isCancelled: { false }
            )
            let seconds = Date().timeIntervalSince(start)
            let attributes = try FileManager.default.attributesOfItem(atPath: out.path)
            let bytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            print("BENCH mode=\(mode.rawValue) seconds=\(seconds) bytes=\(bytes) msgs=\(planned.messages.count) images=\(imageCount)")
        }
    }
}

private func conversationInfo(_ raw: RawConversation, db: DatabaseService) throws -> ConversationInfo {
    let handles = try db.fetchHandlesForChat(chatRowID: raw.rowID)
    let resolver = ContactResolver()
    return ConversationInfo(
        chatRowID: raw.rowID,
        chatGUID: raw.guid,
        displayName: raw.displayName
            ?? handles.first.map { resolver.displayName(for: $0.id) }
            ?? "Unknown",
        participants: handles.map(\.id),
        participantNames: handles.map { resolver.displayName(for: $0.id) },
        messageCount: raw.messageCount,
        lastMessageDate: DateFormatting.dateFromAppleTimestamp(raw.lastMessageDate),
        lastMessagePreview: nil,
        isGroupChat: handles.count > 1,
        serviceName: raw.serviceName ?? "iMessage"
    )
}

private func plan(
    _ conversation: ConversationInfo,
    mode: ExportImageMode,
    db: DatabaseService
) throws -> ExportConversation {
    try ExportPlanner(
        db: db,
        handleMap: try db.fetchAllHandles(),
        contactResolver: ContactResolver()
    ).plan(
        conversation: conversation,
        imageMode: mode,
        progress: { _ in },
        isCancelled: { false }
    )
}

private func tempDocx(_ label: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("iMessagePrinter-\(label)-\(UUID().uuidString).docx")
}
