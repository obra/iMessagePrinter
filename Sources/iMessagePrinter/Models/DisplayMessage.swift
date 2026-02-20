import Foundation
import AppKit

struct Reaction {
    let emoji: String
    let senderName: String
}

struct DisplayAttachment: Identifiable {
    let id: Int64
    let filename: String?
    let transferName: String?
    let mimeType: String?
    let totalBytes: Int64
    let isImage: Bool
    let resolvedPath: String?
    let formattedSize: String
    let image: NSImage?
}

struct DisplayMessage: Identifiable {
    let id: Int64 // message ROWID
    let guid: String
    let text: String?
    let senderName: String
    let senderID: String // raw phone/email
    let isFromMe: Bool
    let date: Date?
    let dateRead: Date?
    let dateDelivered: Date?
    let service: String
    let isDelivered: Bool
    let isRead: Bool
    let isSent: Bool
    let isSystemMessage: Bool
    let isEdited: Bool
    let isRetracted: Bool
    let replyToGUID: String?
    let threadOriginatorGUID: String?
    let groupTitle: String?
    let groupActionType: Int64
    var reactions: [Reaction]
    var attachments: [DisplayAttachment]

    var hasContent: Bool {
        (text != nil && !(text?.isEmpty ?? true)) || !attachments.isEmpty || isSystemMessage || groupTitle != nil
    }

    var formattedLogLine: String {
        let timestamp = DateFormatting.formatDateTime(date)
        let sender = isFromMe ? "Me" : senderName
        let senderDetail = isFromMe ? "" : " (\(senderID))"

        if let groupTitle, groupActionType != 0 {
            return "[\(timestamp)] ** Group renamed to \"\(groupTitle)\" **"
        }

        if isSystemMessage {
            return "[\(timestamp)] ** \(text ?? "System message") **"
        }

        var line = "[\(timestamp)] \(sender)\(senderDetail) [\(service)]: \(text ?? "")"

        if isEdited { line += " (edited)" }
        if isRetracted { line += " (unsent)" }

        return line
    }
}
