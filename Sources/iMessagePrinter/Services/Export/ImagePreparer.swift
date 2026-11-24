import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImagePreparer {
    static func prepare(
        attachments: [ExportAttachment],
        mode: ExportImageMode,
        stagingDirectory: URL,
        onPrepared: @escaping (Int) -> Void,
        isCancelled: @escaping () -> Bool
    ) -> [Int64: PreparedImage] {
        guard mode != .omit else { return [:] }

        let mediaDirectory = stagingDirectory.appendingPathComponent("word/media", isDirectory: true)
        try? FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)

        var prepared: [Int64: PreparedImage] = [:]
        let resultLock = NSLock()

        DispatchQueue.concurrentPerform(iterations: attachments.count) { index in
            if isCancelled() { return }
            let attachment = attachments[index]
            guard attachment.isImage,
                  let path = attachment.resolvedPath,
                  FileManager.default.fileExists(atPath: path) else { return }

            let sourceURL = URL(fileURLWithPath: path)
            guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else { return }

            let image: PreparedImage?
            switch mode {
            case .omit:
                image = nil
            case .thumbnail:
                image = prepareThumbnail(
                    source: source,
                    attachmentID: attachment.id,
                    mediaDirectory: mediaDirectory
                )
            case .fullResolution:
                image = prepareFullResolution(
                    source: source,
                    sourceURL: sourceURL,
                    attachmentID: attachment.id,
                    mediaDirectory: mediaDirectory
                )
            }

            guard let image else { return }

            resultLock.lock()
            prepared[attachment.id] = image
            onPrepared(prepared.count)
            resultLock.unlock()
        }

        return prepared
    }

    private static func prepareThumbnail(
        source: CGImageSource,
        attachmentID: Int64,
        mediaDirectory: URL
    ) -> PreparedImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 640,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let fileName = "image\(attachmentID).jpeg"
        let destination = mediaDirectory.appendingPathComponent(fileName)
        guard writeJPEG(thumbnail, to: destination, quality: 0.85) else { return nil }

        return PreparedImage(
            fileName: fileName,
            pixelWidth: thumbnail.width,
            pixelHeight: thumbnail.height
        )
    }

    private static func prepareFullResolution(
        source: CGImageSource,
        sourceURL: URL,
        attachmentID: Int64,
        mediaDirectory: URL
    ) -> PreparedImage? {
        guard let type = CGImageSourceGetType(source) as String? else { return nil }
        let isPNG = type == UTType.png.identifier
        let isJPEG = type == UTType.jpeg.identifier

        let dimensions = pixelDimensions(of: source)

        if isPNG || isJPEG {
            let ext = isPNG ? "png" : "jpeg"
            let fileName = "image\(attachmentID).\(ext)"
            let destination = mediaDirectory.appendingPathComponent(fileName)
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destination)
            } catch {
                return nil
            }
            return PreparedImage(
                fileName: fileName,
                pixelWidth: dimensions.width,
                pixelHeight: dimensions.height
            )
        }

        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let fileName = "image\(attachmentID).jpeg"
        let destination = mediaDirectory.appendingPathComponent(fileName)
        guard writeJPEG(image, to: destination, quality: 0.9) else { return nil }

        return PreparedImage(
            fileName: fileName,
            pixelWidth: dimensions.width,
            pixelHeight: dimensions.height
        )
    }

    private static func pixelDimensions(of source: CGImageSource) -> (width: Int, height: Int) {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return (0, 0)
        }
        var width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        var height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        if (5...8).contains(orientation) {
            swap(&width, &height)
        }
        return (width, height)
    }

    private static func writeJPEG(_ image: CGImage, to url: URL, quality: Double) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return false
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        return CGImageDestinationFinalize(destination)
    }
}
