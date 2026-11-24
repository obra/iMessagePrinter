import XCTest
@testable import iMessagePrinter

final class DocxPackageTests: XCTestCase {
    func testWritesAValidDocxPackage() throws {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".docx")
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: out)
            try? FileManager.default.removeItem(at: staging)
        }
        var files: [String: Data] = [
            "[Content_Types].xml": Data(DocxWriter.contentTypesXML(hasImages: false).utf8),
            "_rels/.rels": Data(DocxWriter.rootRelationshipsXML().utf8),
            "word/styles.xml": Data(DocxWriter.stylesXML().utf8),
            "word/footer1.xml": Data(DocxWriter.footerXML(conversationName: "Jane").utf8),
            "docProps/core.xml": Data(DocxWriter.corePropertiesXML(title: "Jane", createdAt: Date()).utf8),
            "docProps/app.xml": Data(DocxWriter.appPropertiesXML().utf8),
            "word/document.xml": Data("<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body><w:p><w:r><w:t>Hello &amp; goodbye</w:t></w:r></w:p></w:body></w:document>".utf8),
            "word/_rels/document.xml.rels": Data(DocxWriter.documentRelationshipsXML(imageFileNames: []).utf8),
        ]
        files["word/document.xml"] = Data(
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>Hello &amp; goodbye</w:t></w:r></w:p></w:body></w:document>
            """.utf8
        )
        try DocxPackage(files: files, media: [:]).write(stagingDirectory: staging, to: out)
        try assertValidZip(out)
        let text = try textutilText(out)
        XCTAssertTrue(text.contains("Hello & goodbye"))
        let styles = try zipFileText(out, path: "word/styles.xml")
        XCTAssertTrue(styles.contains("Heading1"))
        XCTAssertTrue(styles.contains("Heading2"))
        XCTAssertTrue(styles.contains("MessageBody"))
    }
}
