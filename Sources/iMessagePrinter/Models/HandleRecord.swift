import Foundation
import GRDB

struct HandleRecord: FetchableRecord, Decodable {
    var rowID: Int64
    var id: String
    var service: String
    var country: String?

    enum CodingKeys: String, CodingKey {
        case rowID = "ROWID"
        case id
        case service
        case country
    }
}
