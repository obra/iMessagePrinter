import Foundation

struct PreparedImage: Equatable {
    let fileName: String
    let pixelWidth: Int
    let pixelHeight: Int
}

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
        <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before="360" w:after="160"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:sz w:val="40"/></w:rPr></w:style>
        <w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before="280" w:after="120"/><w:outlineLvl w:val="1"/></w:pPr><w:rPr><w:b/><w:sz w:val="28"/></w:rPr></w:style>
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

    // MARK: - Document

    static func documentXML(
        conversation: ExportConversation,
        preparedImages: [Int64: PreparedImage],
        exportedAt: Date,
        onRendered: (Int) -> Void = { _ in },
        isCancelled: () -> Bool = { false }
    ) throws -> String {
        var xml = String()
        xml.reserveCapacity(conversation.messages.count * 400 + 4_000)
        xml += """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><w:body>
        """

        xml += paragraphXML(style: "Title", text: "Conversation with \(conversation.displayName)")

        let exportedText = exportDateFormatter.string(from: exportedAt)
        xml += paragraphXML(style: "MessageMeta", text: "Exported \(exportedText)")

        let participantText = zip(conversation.participantNames, conversation.participants)
            .map { name, handle in name == handle ? name : "\(name) (\(handle))" }
            .joined(separator: ", ")
        if !participantText.isEmpty {
            xml += paragraphXML(style: "MessageMeta", text: "Participants: \(participantText)")
        }
        xml += paragraphXML(style: "MessageMeta", text: "Service: \(conversation.serviceName)")
        xml += paragraphXML(style: "MessageMeta", text: "Messages: \(conversation.messages.count)")

        let datedMessages = conversation.messages.compactMap(\.date)
        if let first = datedMessages.first, let last = datedMessages.last {
            let range = "\(shortDateFormatter.string(from: first)) – \(shortDateFormatter.string(from: last))"
            xml += paragraphXML(style: "MessageMeta", text: "Date range: \(range)")
        }

        xml += #"<w:p><w:r><w:br w:type="page"/></w:r></w:p>"#
        xml += paragraphXML(style: "Heading1", text: conversation.displayName)

        let imageIDs = preparedImages.keys.sorted()
        let relationshipIDs = Dictionary(uniqueKeysWithValues: imageIDs.enumerated().map {
            ($0.element, "rIdImage\($0.offset + 1)")
        })

        var previousMonth: String?
        var previousDay: String?
        var drawingIndex = 0
        let batchSize = 250

        for (index, message) in conversation.messages.enumerated() {
            if index % batchSize == 0 {
                if isCancelled() { throw CancellationError() }
                if index > 0 { onRendered(index) }
            }
            guard message.hasContent else { continue }

            let monthLabel = message.date.map { monthFormatter.string(from: $0) } ?? "Undated"
            if monthLabel != previousMonth {
                xml += paragraphXML(style: "Heading2", text: monthLabel)
                previousMonth = monthLabel
            }

            let dayLabel = message.date.map { dateSeparatorFormatter.string(from: $0) } ?? "Undated"
            if dayLabel != previousDay {
                xml += paragraphXML(style: "DateSeparator", text: dayLabel)
                previousDay = dayLabel
            }

            xml += metaParagraphXML(message)

            let bodyText = messageBodyText(message)
            if let bodyText, !bodyText.isEmpty {
                let style = message.isSystemMessage ? "SystemMessage" : "MessageBody"
                xml += bodyParagraphXML(style: style, text: bodyText)
            }

            for reaction in message.reactions {
                xml += paragraphXML(style: "Reaction", text: "\(reaction.emoji) \(reaction.senderName)")
            }

            if message.replyToGUID != nil || message.threadOriginatorGUID != nil {
                xml += paragraphXML(style: "Reaction", text: "Reply in thread")
            }

            for attachment in message.attachments {
                xml += paragraphXML(
                    style: "Attachment",
                    text: "📎 \(attachmentLabel(attachment)) (\(attachment.formattedSize))"
                )
                if let image = preparedImages[attachment.id],
                   let relationshipID = relationshipIDs[attachment.id] {
                    drawingIndex += 1
                    xml += imageParagraphXML(
                        drawingID: drawingIndex,
                        image: image,
                        relationshipID: relationshipID
                    )
                }
            }
        }

        if isCancelled() { throw CancellationError() }
        onRendered(conversation.messages.count)

        xml += #"<w:sectPr><w:footerReference w:type="default" r:id="rIdFooter"/><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>"#
        xml += "</w:body></w:document>"
        return xml
    }

    // MARK: - Timeline helpers

    private static func metaParagraphXML(_ message: ExportMessage) -> String {
        let time = message.date.map { timeFormatter.string(from: $0) } ?? "Unknown time"
        var parts = [time]
        if message.isFromMe {
            parts.append("Me")
        } else {
            var sender = message.senderName
            if message.senderID != message.senderName {
                sender += " (\(message.senderID))"
            }
            parts.append(sender)
        }
        parts.append(message.service)
        if message.isRetracted {
            parts.append("unsent")
        } else if message.isEdited {
            parts.append("edited")
        }
        if message.isFromMe {
            if message.isRead {
                parts.append("read")
            } else if message.isDelivered {
                parts.append("delivered")
            } else if message.isSent {
                parts.append("sent")
            }
        }
        return paragraphXML(style: "MessageMeta", text: parts.joined(separator: " · "))
    }

    private static func messageBodyText(_ message: ExportMessage) -> String? {
        if let text = message.text, !text.isEmpty {
            return text
        }
        if let groupTitle = message.groupTitle, !groupTitle.isEmpty {
            return "Group renamed to \(groupTitle)"
        }
        if message.isSystemMessage {
            return "System message"
        }
        return nil
    }

    private static func attachmentLabel(_ attachment: ExportAttachment) -> String {
        if let transferName = attachment.transferName, !transferName.isEmpty {
            return transferName
        }
        if let filename = attachment.filename, !filename.isEmpty {
            return (filename as NSString).lastPathComponent
        }
        return "Attachment"
    }

    private static func paragraphXML(style: String, text: String) -> String {
        "<w:p><w:pPr><w:pStyle w:val=\"\(style)\"/></w:pPr><w:r><w:t xml:space=\"preserve\">\(XMLText.escape(text))</w:t></w:r></w:p>"
    }

    private static func bodyParagraphXML(style: String, text: String) -> String {
        "<w:p><w:pPr><w:pStyle w:val=\"\(style)\"/></w:pPr>\(runXML(text))</w:p>"
    }

    /// Build one run from escaped text segments so line breaks and tabs are
    /// always emitted as markup, never as text inside <w:t>.
    private static func runXML(_ text: String) -> String {
        var out = "<w:r>"
        for segment in XMLText.segments(text) {
            switch segment {
            case .text(let escaped):
                out += "<w:t xml:space=\"preserve\">\(escaped)</w:t>"
            case .lineBreak:
                out += "<w:br/>"
            case .tab:
                out += "<w:tab/>"
            }
        }
        out += "</w:r>"
        return out
    }

    private static func imageParagraphXML(
        drawingID: Int,
        image: PreparedImage,
        relationshipID: String
    ) -> String {
        let emuPerPixel = 9_525.0
        let maxWidth = 4.5 * 914_400
        let maxHeight = 6.0 * 914_400
        var width = Double(max(image.pixelWidth, 1)) * emuPerPixel
        var height = Double(max(image.pixelHeight, 1)) * emuPerPixel
        let scale = min(1.0, maxWidth / width, maxHeight / height)
        width *= scale
        height *= scale
        let cx = Int(width.rounded())
        let cy = Int(height.rounded())
        let fileName = XMLText.escape(image.fileName)

        return """
        <w:p><w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="\(cx)" cy="\(cy)"/><wp:docPr id="\(drawingID)" name="Picture \(drawingID)"/><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic><pic:nvPicPr><pic:cNvPr id="\(drawingID)" name="\(fileName)"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="\(relationshipID)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>
        """
    }

    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter
    }()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    private static let dateSeparatorFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
}
