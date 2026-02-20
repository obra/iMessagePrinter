import Foundation
import GRDB

final class DatabaseService {
    private let dbQueue: DatabaseQueue

    static let chatDBPath: String = {
        let home = NSHomeDirectory()
        return "\(home)/Library/Messages/chat.db"
    }()

    init() throws {
        var config = Configuration()
        config.readonly = true
        dbQueue = try DatabaseQueue(path: Self.chatDBPath, configuration: config)
    }

    // MARK: - Conversations

    func fetchConversations() throws -> [RawConversation] {
        try dbQueue.read { db in
            let sql = """
                SELECT
                    c.ROWID,
                    c.guid,
                    c.style,
                    c.chat_identifier,
                    c.service_name,
                    c.display_name,
                    COUNT(cmj.message_id) AS message_count,
                    MAX(cmj.message_date) AS last_message_date
                FROM chat c
                LEFT JOIN chat_message_join cmj ON cmj.chat_id = c.ROWID
                GROUP BY c.ROWID
                ORDER BY last_message_date DESC
                """
            return try RawConversation.fetchAll(db, sql: sql)
        }
    }

    func fetchHandlesForChat(chatRowID: Int64) throws -> [HandleRecord] {
        try dbQueue.read { db in
            let sql = """
                SELECT h.ROWID, h.id, h.service, h.country
                FROM handle h
                JOIN chat_handle_join chj ON chj.handle_id = h.ROWID
                WHERE chj.chat_id = ?
                """
            return try HandleRecord.fetchAll(db, sql: sql, arguments: [chatRowID])
        }
    }

    func fetchLastMessagePreview(chatRowID: Int64) throws -> String? {
        try dbQueue.read { db in
            let sql = """
                SELECT m.text, m.attributedBody
                FROM message m
                JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
                WHERE cmj.chat_id = ?
                  AND m.associated_message_type = 0
                ORDER BY m.date DESC
                LIMIT 1
                """
            let row = try Row.fetchOne(db, sql: sql, arguments: [chatRowID])
            if let text = row?["text"] as? String, !text.isEmpty {
                return text
            }
            if let blob = row?["attributedBody"] as? Data {
                return AttributedBodyParser.extractText(from: blob)
            }
            return nil
        }
    }

    // MARK: - Messages

    func fetchMessages(chatRowID: Int64) throws -> [MessageRecord] {
        try dbQueue.read { db in
            let sql = """
                SELECT
                    m.ROWID, m.guid, m.text, m.attributedBody, m.handle_id, m.service,
                    m.date, m.date_read, m.date_delivered,
                    m.is_from_me, m.is_delivered, m.is_read, m.is_sent,
                    m.is_system_message, m.cache_has_attachments,
                    m.associated_message_guid, m.associated_message_type,
                    m.associated_message_emoji, m.associated_message_range_location,
                    m.reply_to_guid, m.thread_originator_guid, m.thread_originator_part,
                    m.group_title, m.group_action_type,
                    m.date_retracted, m.date_edited, m.expressive_send_style_id
                FROM message m
                JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
                WHERE cmj.chat_id = ?
                ORDER BY m.date ASC
                """
            return try MessageRecord.fetchAll(db, sql: sql, arguments: [chatRowID])
        }
    }

    // MARK: - Handles

    func fetchHandle(rowID: Int64) throws -> HandleRecord? {
        try dbQueue.read { db in
            let sql = "SELECT ROWID, id, service, country FROM handle WHERE ROWID = ?"
            return try HandleRecord.fetchOne(db, sql: sql, arguments: [rowID])
        }
    }

    func fetchAllHandles() throws -> [Int64: HandleRecord] {
        try dbQueue.read { db in
            let sql = "SELECT ROWID, id, service, country FROM handle"
            let handles = try HandleRecord.fetchAll(db, sql: sql)
            return Dictionary(uniqueKeysWithValues: handles.map { ($0.rowID, $0) })
        }
    }

    // MARK: - Attachments

    func fetchAttachments(messageRowID: Int64) throws -> [AttachmentRecord] {
        try dbQueue.read { db in
            let sql = """
                SELECT
                    a.ROWID, a.guid, a.filename, a.mime_type, a.uti,
                    a.transfer_name, a.total_bytes, a.transfer_state, a.is_outgoing
                FROM attachment a
                JOIN message_attachment_join maj ON maj.attachment_id = a.ROWID
                WHERE maj.message_id = ?
                """
            return try AttachmentRecord.fetchAll(db, sql: sql, arguments: [messageRowID])
        }
    }
}

// MARK: - Raw Conversation (intermediate fetch result)

struct RawConversation: FetchableRecord, Decodable {
    var rowID: Int64
    var guid: String
    var style: Int64
    var chatIdentifier: String?
    var serviceName: String?
    var displayName: String?
    var messageCount: Int
    var lastMessageDate: Int64?

    enum CodingKeys: String, CodingKey {
        case rowID = "ROWID"
        case guid
        case style
        case chatIdentifier = "chat_identifier"
        case serviceName = "service_name"
        case displayName = "display_name"
        case messageCount = "message_count"
        case lastMessageDate = "last_message_date"
    }
}
