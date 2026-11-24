import Foundation

enum DocxWriter {
    static func contentTypesXML(hasImages: Bool) -> String {
        var parts = [
            #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#,
            #"<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">"#,
            #"<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>"#,
            #"<Default Extension="xml" ContentType="application/xml"/>"#,
        ]
        if hasImages {
            parts.append(#"<Default Extension="png" ContentType="image/png"/>"#)
            parts.append(#"<Default Extension="jpeg" ContentType="image/jpeg"/>"#)
        }
        parts.append(#"<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>"#)
        parts.append(#"<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>"#)
        parts.append(#"<Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>"#)
        parts.append(#"<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>"#)
        parts.append(#"<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>"#)
        parts.append("</Types>")
        return parts.joined()
    }

    static func rootRelationshipsXML() -> String {
        [
            #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#,
            #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">"#,
            #"<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>"#,
            #"<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>"#,
            #"<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>"#,
            "</Relationships>",
        ].joined()
    }

    static func documentRelationshipsXML(imageFileNames: [String]) -> String {
        var parts = [
            #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#,
            #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">"#,
            #"<Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>"#,
            #"<Relationship Id="rIdFooter" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/>"#,
        ]
        for (index, fileName) in imageFileNames.enumerated() {
            let id = "rIdImage\(index + 1)"
            let target = "media/\(XMLText.escape(fileName))"
            parts.append(#"<Relationship Id="\#(id)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="\#(target)"/>"#)
        }
        parts.append("</Relationships>")
        return parts.joined()
    }

    static func stylesXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:sz w:val="22"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="80"/></w:pPr></w:pPrDefault></w:docDefaults>
        <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>
        <w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:rPr><w:b/><w:sz w:val="56"/></w:rPr></w:style>
        <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:outlineLvl w:val="0"/><w:spacing w:before="360" w:after="160"/></w:pPr><w:rPr><w:b/><w:sz w:val="40"/></w:rPr></w:style>
        <w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:outlineLvl w:val="1"/><w:spacing w:before="280" w:after="120"/></w:pPr><w:rPr><w:b/><w:sz w:val="28"/></w:rPr></w:style>
        <w:style w:type="paragraph" w:styleId="MessageMeta"><w:name w:val="Message Meta"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="120" w:after="20"/></w:pPr><w:rPr><w:b/><w:sz w:val="18"/></w:rPr></w:style>
        <w:style w:type="paragraph" w:styleId="MessageBody"><w:name w:val="Message Body"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:after="80"/></w:pPr><w:rPr><w:sz w:val="21"/></w:rPr></w:style>
        <w:style w:type="paragraph" w:styleId="DateSeparator"><w:name w:val="Date Separator"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="240" w:after="80"/></w:pPr><w:rPr><w:b/><w:color w:val="666666"/><w:sz w:val="18"/></w:rPr></w:style>
        <w:style w:type="paragraph" w:styleId="Reaction"><w:name w:val="Reaction"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="20"/></w:pPr><w:rPr><w:i/><w:color w:val="555555"/><w:sz w:val="18"/></w:rPr></w:style>
        <w:style w:type="paragraph" w:styleId="Attachment"><w:name w:val="Attachment"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="40"/></w:pPr><w:rPr><w:color w:val="444444"/><w:sz w:val="18"/></w:rPr></w:style>
        <w:style w:type="paragraph" w:styleId="SystemMessage"><w:name w:val="System Message"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="60"/></w:pPr><w:rPr><w:i/><w:color w:val="777777"/><w:sz w:val="19"/></w:rPr></w:style>
        </w:styles>
        """
    }

    static func footerXML(conversationName: String) -> String {
        let name = XMLText.escape(conversationName)
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:ftr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:sz w:val="16"/></w:rPr><w:t xml:space="preserve">\(name) — Page </w:t></w:r><w:fldSimple w:instr=" PAGE "><w:r><w:rPr><w:sz w:val="16"/></w:rPr><w:t>1</w:t></w:r></w:fldSimple><w:r><w:rPr><w:sz w:val="16"/></w:rPr><w:t xml:space="preserve"> of </w:t></w:r><w:fldSimple w:instr=" NUMPAGES "><w:r><w:rPr><w:sz w:val="16"/></w:rPr><w:t>1</w:t></w:r></w:fldSimple></w:p>
        </w:ftr>
        """
    }

    static func corePropertiesXML(title: String, createdAt: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: createdAt)
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><dc:title>\(XMLText.escape(title))</dc:title><dc:creator>iMessagePrinter</dc:creator><cp:lastModifiedBy>iMessagePrinter</cp:lastModifiedBy><dcterms:created xsi:type="dcterms:W3CDTF">\(timestamp)</dcterms:created><dcterms:modified xsi:type="dcterms:W3CDTF">\(timestamp)</dcterms:modified></cp:coreProperties>
        """
    }

    static func appPropertiesXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes"><Application>iMessagePrinter</Application></Properties>
        """
    }
}
