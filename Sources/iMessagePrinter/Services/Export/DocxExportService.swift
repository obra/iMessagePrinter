import Foundation

enum DocxExportService {
    static func export(
        conversation: ExportConversation,
        imageMode: ExportImageMode,
        to url: URL,
        progress: @escaping (ExportProgress) -> Void,
        isCancelled: @escaping () -> Bool,
        writePackage: ((DocxPackage, URL, URL) throws -> Void)? = nil
    ) throws {
        let fileManager = FileManager.default
        let staging = fileManager.temporaryDirectory
            .appendingPathComponent("iMessagePrinter-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        if isCancelled() {
            throw CancellationError()
        }

        var seenAttachmentIDs = Set<Int64>()
        let exportableImages = conversation.messages
            .flatMap(\.attachments)
            .filter { attachment in
                guard attachment.isImage,
                      let path = attachment.resolvedPath,
                      seenAttachmentIDs.insert(attachment.id).inserted else { return false }
                return fileManager.fileExists(atPath: path)
            }

        var estimator = ExportProgressEstimator(
            totalMessages: conversation.messages.count,
            totalImages: exportableImages.count
        )
        estimator.setFractionRange(0.1...0.95)
        estimator.setPhase(.preparing)
        progress(estimator.snapshot)

        estimator.setPhase(.images)
        progress(estimator.snapshot)
        let preparedImages = ImagePreparer.prepare(
            attachments: exportableImages,
            mode: imageMode,
            stagingDirectory: staging,
            onPrepared: { _ in
                estimator.imageCompleted()
                progress(estimator.snapshot)
            },
            isCancelled: isCancelled
        )

        if isCancelled() {
            throw CancellationError()
        }

        if imageMode == .omit {
            for _ in exportableImages {
                estimator.imageCompleted()
            }
        }

        estimator.setPhase(.rendering)
        let imageIDs = preparedImages.keys.sorted()
        let imageFileNames = imageIDs.compactMap { preparedImages[$0]?.fileName }
        let exportedAt = Date()

        let files: [String: Data] = [
            "[Content_Types].xml": Data(DocxWriter.contentTypesXML(hasImages: !preparedImages.isEmpty).utf8),
            "_rels/.rels": Data(DocxWriter.rootRelationshipsXML().utf8),
            "word/styles.xml": Data(DocxWriter.stylesXML().utf8),
            "word/_rels/document.xml.rels": Data(DocxWriter.documentRelationshipsXML(
                imageFileNames: imageFileNames
            ).utf8),
            "word/footer1.xml": Data(DocxWriter.footerXML(conversationName: conversation.displayName).utf8),
            "docProps/core.xml": Data(DocxWriter.corePropertiesXML(
                title: conversation.displayName,
                createdAt: exportedAt
            ).utf8),
            "docProps/app.xml": Data(DocxWriter.appPropertiesXML().utf8),
        ]

        var countedMessages = 0
        let documentXML = try DocxWriter.documentXML(
            conversation: conversation,
            preparedImages: preparedImages,
            exportedAt: exportedAt,
            onRendered: { processed in
                while countedMessages < processed {
                    estimator.messageCompleted()
                    countedMessages += 1
                }
                progress(estimator.snapshot)
            },
            isCancelled: isCancelled
        )

        var packagedFiles = files
        packagedFiles["word/document.xml"] = Data(documentXML.utf8)

        estimator.setPhase(.compressing)
        progress(estimator.snapshot)

        let package = DocxPackage(files: packagedFiles, media: [:])
        if let writePackage {
            try writePackage(package, staging, url)
        } else {
            try package.write(stagingDirectory: staging, to: url, isCancelled: isCancelled)
        }

        estimator.setPhase(.finishing)
        var final = estimator.snapshot
        final.fraction = 1.0
        final.estimatedRemaining = nil
        progress(final)
    }
}
