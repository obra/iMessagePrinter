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

        var seenIDs = Set<Int64>()
        let uniqueAttachments = attachments.filter { seenIDs.insert($0.id).inserted }

        var prepared: [Int64: PreparedImage] = [:]
        let resultLock = NSLock()
        // Full-resolution decoding produces one full-size raster per worker.
        // Keeping that low bounds peak memory on conversations with many large
        // photos while still overlapping file I/O.
        let fullResolutionWorkers = min(4, ProcessInfo.processInfo.activeProcessorCount)
        let workerCount = min(
            uniqueAttachments.count,
            mode == .fullResolution ? fullResolutionWorkers : ProcessInfo.processInfo.activeProcessorCount
        )
        guard workerCount > 0 else { return [:] }

        DispatchQueue.concurrentPerform(iterations: workerCount) { worker in
            var index = worker
            while index < uniqueAttachments.count {
                if isCancelled() { return }
                let attachment = uniqueAttachments[index]
                index += workerCount
                guard attachment.isImage,
                      let path = attachment.resolvedPath,
                      FileManager.default.fileExists(atPath: path) else { continue }

                let sourceURL = URL(fileURLWithPath: path)
                guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else { continue }

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

                guard let image else { continue }

                resultLock.lock()
                prepared[attachment.id] = image
                onPrepared(prepared.count)
                resultLock.unlock()
            }
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
            guard CGImageSourceCreateImageAtIndex(
                source,
                0,
                [kCGImageSourceShouldCache: false] as CFDictionary
            ) != nil else {
                // ImageIO can recognize a truncated file's type while failing to
                // decode it. Copying it would embed bytes Word cannot render.
                return nil
            }
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
