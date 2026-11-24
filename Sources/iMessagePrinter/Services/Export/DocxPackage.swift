import Foundation

enum DocxError: LocalizedError {
    case zipFailed(Int32, String)
    case cannotCreatePackage

    var errorDescription: String? {
        switch self {
        case .zipFailed(let status, let message):
            return "Could not package the Word document (zip exited \(status)): \(message)"
        case .cannotCreatePackage:
            return "Could not create the Word document package."
        }
    }
}

struct DocxPackage {
    var files: [String: Data]
    var media: [String: URL]

    func write(stagingDirectory: URL, to url: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)

        for (relativePath, data) in files {
            let destination = stagingDirectory.appendingPathComponent(relativePath)
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: destination)
        }

        for (relativePath, source) in media {
            let destination = stagingDirectory.appendingPathComponent(relativePath)
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
        }

        let temporaryArchive = url.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).docx")
        try? fileManager.removeItem(at: temporaryArchive)

        do {
            try ZipPackager.zip(stagingDirectory: stagingDirectory, outputURL: temporaryArchive)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            try fileManager.moveItem(at: temporaryArchive, to: url)
        } catch {
            try? fileManager.removeItem(at: temporaryArchive)
            throw error
        }
    }
}
