import Foundation

struct ConversationInfo: Identifiable, Hashable {
    let chatRowID: Int64
    let chatGUID: String
    let displayName: String
    let participants: [String] // handle IDs (phone/email)
    let participantNames: [String] // resolved display names
    let messageCount: Int
    let lastMessageDate: Date?
    let lastMessagePreview: String?
    let isGroupChat: Bool
    let serviceName: String

    var id: Int64 { chatRowID }
}
