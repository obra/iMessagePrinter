import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import iMessagePrinter

final class DocxImageTests: XCTestCase {
    func testThumbnailIsWrittenAndReferenced() throws {
        let path = try makePNG(width: 4, height: 2)
        let attachment = makeAttachment(path: path)
        let staging = try makeStagingDirectory()

        let images = ImagePreparer.prepare(
            attachments: [attachment],
            mode: .thumbnail,
            stagingDirectory: staging,
            onPrepared: { _ in },
            isCancelled: { false }
        )
        let prepared = try XCTUnwrap(images[attachment.id])
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: staging.appendingPathComponent("word/media/\(prepared.fileName)").path
        ))
        XCTAssertLessThanOrEqual(max(prepared.pixelWidth, prepared.pixelHeight), 640)

        let xml = try DocxWriter.documentXML(
            conversation: conversationWith(attachment),
            preparedImages: images,
            exportedAt: Date()
        )
        XCTAssertTrue(xml.contains("<w:drawing>"))
        XCTAssertTrue(xml.contains("r:embed=\"rIdImage1\""))
    }

    func testOmitModeReturnsNoImages() throws {
        let attachment = makeAttachment(path: try makePNG(width: 4, height: 2))
        let staging = try makeStagingDirectory()
        let images = ImagePreparer.prepare(
            attachments: [attachment],
            mode: .omit,
            stagingDirectory: staging,
            onPrepared: { _ in },
            isCancelled: { false }
        )
        XCTAssertTrue(images.isEmpty)
    }

    func testMissingFileFallsBackToFilenameLabel() throws {
        let attachment = makeAttachment(path: "/tmp/does-not-exist-\(UUID().uuidString).png", name: "missing.png")
        let staging = try makeStagingDirectory()
        let images = ImagePreparer.prepare(
            attachments: [attachment],
            mode: .thumbnail,
            stagingDirectory: staging,
            onPrepared: { _ in },
            isCancelled: { false }
        )
        XCTAssertTrue(images.isEmpty)

        let xml = try DocxWriter.documentXML(
            conversation: conversationWith(attachment),
            preparedImages: images,
            exportedAt: Date()
        )
        XCTAssertTrue(xml.contains("missing.png"))
    }

    func testFullResolutionPNGKeepsOriginalDimensions() throws {
        let path = try makePNG(width: 4, height: 2)
        let attachment = makeAttachment(path: path)
        let staging = try makeStagingDirectory()
        let images = ImagePreparer.prepare(
            attachments: [attachment],
            mode: .fullResolution,
            stagingDirectory: staging,
            onPrepared: { _ in },
            isCancelled: { false }
        )
        let prepared = try XCTUnwrap(images[attachment.id])
        XCTAssertEqual(prepared.pixelWidth, 4)
        XCTAssertEqual(prepared.pixelHeight, 2)
        XCTAssertTrue(prepared.fileName.hasSuffix(".png"))
    }

    func testLargeImageThumbnailIsCappedAt640() throws {
        let attachment = makeAttachment(path: try makePNG(width: 4000, height: 3000))
        let staging = try makeStagingDirectory()
        let images = ImagePreparer.prepare(
            attachments: [attachment],
            mode: .thumbnail,
            stagingDirectory: staging,
            onPrepared: { _ in },
            isCancelled: { false }
        )
        let prepared = try XCTUnwrap(images[attachment.id])
        XCTAssertLessThanOrEqual(max(prepared.pixelWidth, prepared.pixelHeight), 640)
    }

    func testCorruptFileReturnsNoEntry() throws {
        let directory = try makeTempDirectory()
        let path = directory.appendingPathComponent("corrupt.png")
        try Data("not an image".utf8).write(to: path)
        let attachment = makeAttachment(path: path.path)
        let staging = try makeStagingDirectory()

        let images = ImagePreparer.prepare(
            attachments: [attachment],
            mode: .thumbnail,
            stagingDirectory: staging,
            onPrepared: { _ in },
            isCancelled: { false }
        )
        XCTAssertTrue(images.isEmpty)
    }
}

private func makeAttachment(
    path: String,
    name: String = "photo.png",
    id: Int64 = 1
) -> ExportAttachment {
    ExportAttachment(
        id: id,
        filename: path,
        transferName: name,
        mimeType: "image/png",
        totalBytes: 100,
        isImage: true,
        resolvedPath: path,
        formattedSize: "100 bytes"
    )
}

private func conversationWith(_ attachment: ExportAttachment) -> ExportConversation {
    ExportConversation(
        chatRowID: 1,
        chatGUID: "chat-1",
        displayName: "Jane",
        participants: ["+15551234567"],
        participantNames: ["Jane"],
        serviceName: "iMessage",
        isGroupChat: false,
        messages: [
            ExportMessage(
                id: 1,
                guid: "m1",
                text: "photo",
                senderName: "Jane",
                senderID: "+15551234567",
                isFromMe: false,
                date: Date(timeIntervalSince1970: 1_700_000_000),
                dateRead: nil,
                dateDelivered: nil,
                service: "iMessage",
                isDelivered: true,
                isRead: true,
                isSent: true,
                isSystemMessage: false,
                isEdited: false,
                isRetracted: false,
                replyToGUID: nil,
                threadOriginatorGUID: nil,
                groupTitle: nil,
                groupActionType: 0,
                reactions: [],
                attachments: [attachment]
            )
        ]
    )
}

private func makePNG(width: Int, height: Int) throws -> String {
    let directory = try makeTempDirectory()
    let url = directory.appendingPathComponent("\(UUID().uuidString).png")
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = try XCTUnwrap(CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try XCTUnwrap(context.makeImage())
    let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ))
    CGImageDestinationAddImage(destination, image, nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return url.path
}

private func makeStagingDirectory() throws -> URL {
    try makeTempDirectory().appendingPathComponent("staging", isDirectory: true)
}

private func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("DocxImageTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
