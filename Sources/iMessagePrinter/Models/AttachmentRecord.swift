import Foundation
import GRDB

struct AttachmentRecord: FetchableRecord, Decodable {
    var rowID: Int64
    var guid: String
    var filename: String?
    var mimeType: String?
    var uti: String?
    var transferName: String?
    var totalBytes: Int64
    var transferState: Int64
    var isOutgoing: Bool

    enum CodingKeys: String, CodingKey {
        case rowID = "ROWID"
        case guid
        case filename
        case mimeType = "mime_type"
        case uti
        case transferName = "transfer_name"
        case totalBytes = "total_bytes"
        case transferState = "transfer_state"
        case isOutgoing = "is_outgoing"
    }

    var isImage: Bool {
        mimeType?.hasPrefix("image/") == true
    }

    var isVideo: Bool {
        mimeType?.hasPrefix("video/") == true
    }

    /// Expand ~ in filename to full home directory path
    var resolvedPath: String? {
        guard let filename else { return nil }
        if filename.hasPrefix("~") {
            return NSString(string: filename).expandingTildeInPath
        }
        return filename
    }

    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalBytes)
    }

    var isDownloaded: Bool {
        transferState == 5 || transferState == 0
    }
}
