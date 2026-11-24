import Darwin
import Foundation

/// Publication of finished export files.
///
/// Exports are written to a temporary sibling of the destination and moved into
/// place only after the whole document is complete, so a failure never deletes
/// or truncates a file the user already had.
enum AtomicFile {
    static func temporarySibling(of url: URL) -> URL {
        url.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString)\(url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)")")
    }

    static func publish(_ temporary: URL, to url: URL) throws {
        if rename(temporary.path, url.path) != 0 {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
