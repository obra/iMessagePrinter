import Foundation
import GRDB

struct MessageRecord: FetchableRecord, Decodable {
    var rowID: Int64
    var guid: String
    var text: String?
    var attributedBody: Data?
    var handleID: Int64
    var service: String?
    var date: Int64?
    var dateRead: Int64?
    var dateDelivered: Int64?
    var isFromMe: Bool
    var isDelivered: Bool
    var isRead: Bool
    var isSent: Bool
    var isSystemMessage: Bool
    var cacheHasAttachments: Bool
    var associatedMessageGUID: String?
    var associatedMessageType: Int64
    var associatedMessageEmoji: String?
    var associatedMessageRangeLocation: Int64
    var replyToGUID: String?
    var threadOriginatorGUID: String?
    var threadOriginatorPart: String?
    var groupTitle: String?
    var groupActionType: Int64
    var dateRetracted: Int64?
    var dateEdited: Int64?
    var expressive_send_style_id: String?

    enum CodingKeys: String, CodingKey {
        case rowID = "ROWID"
        case guid
        case text
        case attributedBody
        case handleID = "handle_id"
        case service
        case date
        case dateRead = "date_read"
        case dateDelivered = "date_delivered"
        case isFromMe = "is_from_me"
        case isDelivered = "is_delivered"
        case isRead = "is_read"
        case isSent = "is_sent"
        case isSystemMessage = "is_system_message"
        case cacheHasAttachments = "cache_has_attachments"
        case associatedMessageGUID = "associated_message_guid"
        case associatedMessageType = "associated_message_type"
        case associatedMessageEmoji = "associated_message_emoji"
        case associatedMessageRangeLocation = "associated_message_range_location"
        case replyToGUID = "reply_to_guid"
        case threadOriginatorGUID = "thread_originator_guid"
        case threadOriginatorPart = "thread_originator_part"
        case groupTitle = "group_title"
        case groupActionType = "group_action_type"
        case dateRetracted = "date_retracted"
        case dateEdited = "date_edited"
        case expressive_send_style_id
    }

    var isReaction: Bool {
        associatedMessageType >= 2000 && associatedMessageType <= 2006
    }

    var isReactionRemoval: Bool {
        associatedMessageType >= 3000 && associatedMessageType <= 3006
    }

    var reactionType: String? {
        if let emoji = associatedMessageEmoji, !emoji.isEmpty {
            return emoji
        }
        switch associatedMessageType {
        case 2000, 3000: return "\u{2764}\u{FE0F}" // ❤️
        case 2001, 3001: return "\u{1F44D}" // 👍
        case 2002, 3002: return "\u{1F44E}" // 👎
        case 2003, 3003: return "\u{1F602}" // 😂
        case 2004, 3004: return "\u{2757}\u{2757}" // ‼️
        case 2005, 3005: return "\u{2753}" // ❓
        default: return nil
        }
    }

    /// Extract the target message GUID from associated_message_guid (format: "p:N/GUID")
    var targetMessageGUID: String? {
        guard let raw = associatedMessageGUID else { return nil }
        if let slashIndex = raw.firstIndex(of: "/") {
            return String(raw[raw.index(after: slashIndex)...])
        }
        return raw
    }
}
