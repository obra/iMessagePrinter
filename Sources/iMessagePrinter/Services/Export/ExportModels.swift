import Foundation

enum ExportImageMode: Int, CaseIterable {
    case omit = 0
    case thumbnail = 1
    case fullResolution = 2

    var label: String {
        switch self {
        case .omit: return "No images"
        case .thumbnail: return "Thumbnails (640\u{00D7}480)"
        case .fullResolution: return "Full resolution"
        }
    }
}

enum ExportFormat {
    case pdf
    case docx

    var fileExtension: String {
        switch self {
        case .pdf: return "pdf"
        case .docx: return "docx"
        }
    }

    var defaultNameSuffix: String {
        switch self {
        case .pdf: return "- Messages.pdf"
        case .docx: return "- Messages.docx"
        }
    }
}

struct ExportAttachment: Identifiable, Equatable {
    let id: Int64
    let filename: String?
    let transferName: String?
    let mimeType: String?
    let totalBytes: Int64
    let isImage: Bool
    let resolvedPath: String?
    let formattedSize: String
}

struct ExportMessage: Identifiable {
    let id: Int64
    let guid: String
    let text: String?
    let senderName: String
    let senderID: String
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
    let reactions: [Reaction]
    let attachments: [ExportAttachment]

    var hasContent: Bool {
        (text != nil && !(text?.isEmpty ?? true))
            || !attachments.isEmpty
            || isSystemMessage
            || groupTitle != nil
    }
}

struct ExportConversation {
    let chatRowID: Int64
    let chatGUID: String
    let displayName: String
    let participants: [String]
    let participantNames: [String]
    let serviceName: String
    let isGroupChat: Bool
    let messages: [ExportMessage]
}
