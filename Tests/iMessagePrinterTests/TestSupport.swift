import Foundation
import GRDB
import XCTest
@testable import iMessagePrinter

let fixtureTypedStreamText = "from typedstream"

final class Fixture {
    let directory: URL
    let dbPath: String
    let db: DatabaseService

    init(directory: URL, dbPath: String, db: DatabaseService) {
        self.directory = directory
        self.dbPath = dbPath
        self.db = db
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func executeSQL(_ sql: String) throws {
        let queue = try DatabaseQueue(path: dbPath)
        try queue.write { db in
            try db.execute(sql: sql)
        }
    }
}

func makeFixture() throws -> Fixture {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("iMessagePrinterTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let dbPath = directory.appendingPathComponent("chat.db").path

    let queue = try DatabaseQueue(path: dbPath)
    try queue.write { db in
        for statement in fixtureSchema {
            try db.execute(sql: statement)
        }
        for statement in fixtureRows {
            try db.execute(sql: statement)
        }
        let typedStream = Data("NSString".utf8)
            + Data([0x84, 0x84, UInt8(fixtureTypedStreamText.utf8.count)])
            + Data(fixtureTypedStreamText.utf8)
        try db.execute(
            sql: "UPDATE message SET attributedBody = ? WHERE ROWID = 3",
            arguments: [typedStream]
        )
    }

    return Fixture(directory: directory, dbPath: dbPath, db: try DatabaseService(path: dbPath))
}

func fixtureConversation(_ fixture: Fixture, chatRowID: Int64) throws -> ConversationInfo {
    switch chatRowID {
    case 1:
        return ConversationInfo(
            chatRowID: 1,
            chatGUID: "chat-1",
            displayName: "Test Person",
            participants: ["+15551234567"],
            participantNames: ["Test Person"],
            messageCount: 4,
            lastMessageDate: nil,
            lastMessagePreview: nil,
            isGroupChat: false,
            serviceName: "iMessage"
        )
    case 2:
        return ConversationInfo(
            chatRowID: 2,
            chatGUID: "chat-2",
            displayName: "Other Person",
            participants: ["+15559876543"],
            participantNames: ["Other Person"],
            messageCount: 1,
            lastMessageDate: nil,
            lastMessagePreview: nil,
            isGroupChat: false,
            serviceName: "iMessage"
        )
    default:
        throw FixtureError.unknownChat(chatRowID)
    }
}

func planChat1(_ fixture: Fixture, imageMode: ExportImageMode = .omit) throws -> ExportConversation {
    try ExportPlanner(
        db: fixture.db,
        handleMap: fixture.db.fetchAllHandles(),
        contactResolver: ContactResolver()
    ).plan(
        conversation: fixtureConversation(fixture, chatRowID: 1),
        imageMode: imageMode,
        progress: { _ in },
        isCancelled: { false }
    )
}

enum FixtureError: Error {
    case unknownChat(Int64)
}

func assertValidZip(_ url: URL, file: StaticString = #filePath, line: UInt = #line) throws {
    let result = try runTool("/usr/bin/unzip", ["-t", url.path])
    if result.status != 0 {
        XCTFail("unzip -t failed: \(result.stderr)", file: file, line: line)
    }
}

func textutilText(_ url: URL) throws -> String {
    try runTool("/usr/bin/textutil", ["-convert", "txt", "-stdout", url.path]).stdout
}

func zipFileText(_ url: URL, path: String) throws -> String {
    try runTool("/usr/bin/unzip", ["-p", url.path, path]).stdout
}

private struct ToolResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

private func runTool(_ executable: String, _ arguments: [String]) throws -> ToolResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()
    process.waitUntilExit()

    let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return ToolResult(status: process.terminationStatus, stdout: stdout, stderr: stderr)
}

private let fixtureSchema = [
    "CREATE TABLE handle (ROWID INTEGER PRIMARY KEY, id TEXT NOT NULL, service TEXT NOT NULL, country TEXT)",
    "CREATE TABLE chat (ROWID INTEGER PRIMARY KEY, guid TEXT NOT NULL, style INTEGER NOT NULL DEFAULT 0, chat_identifier TEXT, service_name TEXT, display_name TEXT)",
    "CREATE TABLE chat_handle_join (chat_id INTEGER NOT NULL, handle_id INTEGER NOT NULL)",
    """
    CREATE TABLE message (
        ROWID INTEGER PRIMARY KEY,
        guid TEXT NOT NULL,
        text TEXT,
        attributedBody BLOB,
        handle_id INTEGER NOT NULL DEFAULT 0,
        service TEXT,
        date INTEGER,
        date_read INTEGER,
        date_delivered INTEGER,
        is_from_me INTEGER NOT NULL DEFAULT 0,
        is_delivered INTEGER NOT NULL DEFAULT 0,
        is_read INTEGER NOT NULL DEFAULT 0,
        is_sent INTEGER NOT NULL DEFAULT 0,
        is_system_message INTEGER NOT NULL DEFAULT 0,
        cache_has_attachments INTEGER NOT NULL DEFAULT 0,
        associated_message_guid TEXT,
        associated_message_type INTEGER NOT NULL DEFAULT 0,
        associated_message_emoji TEXT,
        associated_message_range_location INTEGER NOT NULL DEFAULT 0,
        reply_to_guid TEXT,
        thread_originator_guid TEXT,
        thread_originator_part TEXT,
        group_title TEXT,
        group_action_type INTEGER NOT NULL DEFAULT 0,
        date_retracted INTEGER,
        date_edited INTEGER,
        expressive_send_style_id TEXT
    )
    """,
    "CREATE TABLE chat_message_join (chat_id INTEGER NOT NULL, message_id INTEGER NOT NULL, message_date INTEGER)",
    "CREATE TABLE attachment (ROWID INTEGER PRIMARY KEY, guid TEXT NOT NULL, filename TEXT, mime_type TEXT, uti TEXT, transfer_name TEXT, total_bytes INTEGER NOT NULL DEFAULT 0, transfer_state INTEGER NOT NULL DEFAULT 0, is_outgoing INTEGER NOT NULL DEFAULT 0)",
    "CREATE TABLE message_attachment_join (message_id INTEGER NOT NULL, attachment_id INTEGER NOT NULL)",
]

private let fixtureRows = [
    "INSERT INTO handle (ROWID, id, service) VALUES (10, '+15551234567', 'iMessage')",
    "INSERT INTO handle (ROWID, id, service) VALUES (11, '+15559876543', 'iMessage')",
    "INSERT INTO chat (ROWID, guid, style, chat_identifier, service_name) VALUES (1, 'chat-1', 45, '+15551234567', 'iMessage')",
    "INSERT INTO chat (ROWID, guid, style, chat_identifier, service_name) VALUES (2, 'chat-2', 45, '+15559876543', 'iMessage')",
    "INSERT INTO chat_handle_join (chat_id, handle_id) VALUES (1, 10)",
    "INSERT INTO chat_handle_join (chat_id, handle_id) VALUES (2, 11)",
    "INSERT INTO message (ROWID, guid, text, handle_id, service, date) VALUES (1, 'msg-1', 'original', 10, 'iMessage', 100)",
    "INSERT INTO message (ROWID, guid, text, handle_id, service, date, cache_has_attachments) VALUES (2, 'msg-2', 'second', 10, 'iMessage', 200, 1)",
    "INSERT INTO message (ROWID, guid, text, handle_id, service, date) VALUES (3, 'msg-3', NULL, 10, 'iMessage', 300)",
    "INSERT INTO message (ROWID, guid, text, handle_id, service, date) VALUES (4, 'msg-4', 'other chat', 10, 'iMessage', 150)",
    "INSERT INTO message (ROWID, guid, handle_id, service, date, associated_message_guid, associated_message_type) VALUES (5, 'msg-5', 10, 'iMessage', 350, 'p:0/msg-1', 2000)",
    "INSERT INTO chat_message_join (chat_id, message_id, message_date) VALUES (1, 1, 100)",
    "INSERT INTO chat_message_join (chat_id, message_id, message_date) VALUES (1, 2, 200)",
    "INSERT INTO chat_message_join (chat_id, message_id, message_date) VALUES (1, 3, 300)",
    "INSERT INTO chat_message_join (chat_id, message_id, message_date) VALUES (1, 5, 350)",
    "INSERT INTO chat_message_join (chat_id, message_id, message_date) VALUES (2, 4, 150)",
    "INSERT INTO attachment (ROWID, guid, filename, mime_type, uti, transfer_name, total_bytes, transfer_state) VALUES (1, 'att-1', '/tmp/photo.jpg', 'image/jpeg', 'public.jpeg', 'photo.jpg', 1234, 5)",
    "INSERT INTO message_attachment_join (message_id, attachment_id) VALUES (2, 1)",
]
