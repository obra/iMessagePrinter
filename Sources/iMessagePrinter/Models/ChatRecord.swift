import Foundation
import GRDB

struct ChatRecord: FetchableRecord, Decodable {
    var rowID: Int64
    var guid: String
    var style: Int64
    var chatIdentifier: String?
    var serviceName: String?
    var displayName: String?

    enum CodingKeys: String, CodingKey {
        case rowID = "ROWID"
        case guid
        case style
        case chatIdentifier = "chat_identifier"
        case serviceName = "service_name"
        case displayName = "display_name"
    }

    var isGroupChat: Bool { style == 43 }
}
