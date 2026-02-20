import Foundation
import AppKit

enum PDFExportService {
    // MARK: - Layout

    private static let pageWidth: CGFloat = 612
    private static let pageHeight: CGFloat = 792
    private static let margin: CGFloat = 54
    private static let usableWidth: CGFloat = 612 - 108
    private static let timeWidth: CGFloat = 46     // column for outdented timestamps
    private static let contentIndent: CGFloat = 52 // text starts after timestamp column
    private static let contentWidth: CGFloat = 612 - 108 - 52
    private static let maxImageWidth: CGFloat = 260
    private static let maxImageHeight: CGFloat = 200

    // MARK: - Colors

    private static let accentBlue = NSColor(calibratedRed: 0.20, green: 0.45, blue: 0.85, alpha: 1.0)
    private static let senderMe = NSColor(calibratedRed: 0.15, green: 0.55, blue: 0.30, alpha: 1.0)
    private static let senderOther = NSColor(calibratedRed: 0.20, green: 0.35, blue: 0.70, alpha: 1.0)
    private static let gray50 = NSColor(calibratedWhite: 0.50, alpha: 1.0)
    private static let gray65 = NSColor(calibratedWhite: 0.65, alpha: 1.0)
    private static let gray15 = NSColor(calibratedWhite: 0.15, alpha: 1.0)
    private static let ruleColor = NSColor(calibratedWhite: 0.83, alpha: 1.0)
    private static let purple = NSColor(calibratedRed: 0.55, green: 0.30, blue: 0.65, alpha: 1.0)

    // MARK: - Fonts

    private static let fTitle = NSFont.systemFont(ofSize: 22, weight: .bold)
    private static let fSubtitle = NSFont.systemFont(ofSize: 11, weight: .medium)
    private static let fLabel = NSFont.systemFont(ofSize: 9, weight: .semibold)
    private static let fValue = NSFont.systemFont(ofSize: 9, weight: .regular)
    private static let fSender = NSFont.systemFont(ofSize: 9.5, weight: .semibold)
    private static let fBody = NSFont.systemFont(ofSize: 9.5, weight: .regular)
    private static let fMeta = NSFont.systemFont(ofSize: 7.5, weight: .regular)
    private static let fTime = NSFont.monospacedDigitSystemFont(ofSize: 7.5, weight: .regular)
    private static let fReaction = NSFont.systemFont(ofSize: 8, weight: .medium)
    private static let fSystem = NSFont.systemFont(ofSize: 8.5, weight: .medium)
    private static let fDateSep = NSFont.systemFont(ofSize: 8, weight: .semibold)
    private static let fFooter = NSFont.monospacedDigitSystemFont(ofSize: 7, weight: .regular)

    // MARK: - Attachment Mode

    enum AttachmentMode: Int, CaseIterable {
        case omit = 0
        case thumbnail = 1
        case fullResolution = 2

        var label: String {
            switch self {
            case .omit: return "No images"
            case .thumbnail: return "Thumbnails (640\u{00D7}480)"
            case .fullResolution: return "Full resolution"
            }
        }
    }

    // MARK: - Export

    static func export(
        conversation: ConversationInfo,
        messages: [DisplayMessage],
        attachmentMode: AttachmentMode,
        to url: URL
    ) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let ctx = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw ExportError.cannotCreatePDF
        }

        var y: CGFloat = 0
        var pageNum = 0

        func beginPage() {
            pageNum += 1
            ctx.beginPDFPage(nil)
            y = pageHeight - margin
        }

        func endPage() {
            drawFooter(ctx: ctx, page: pageNum, name: conversation.displayName)
            ctx.endPDFPage()
        }

        func ensureSpace(_ needed: CGFloat) {
            if y - needed < margin {
                endPage()
                beginPage()
            }
        }

        /// Draw an NSAttributedString at (x, current y), return height consumed
        func drawBlock(_ str: NSAttributedString, x: CGFloat, width: CGFloat) -> CGFloat {
            let setter = CTFramesetterCreateWithAttributedString(str)
            let size = CTFramesetterSuggestFrameSizeWithConstraints(
                setter, CFRange(location: 0, length: str.length), nil,
                CGSize(width: width, height: .greatestFiniteMagnitude), nil
            )
            let rect = CGRect(x: x, y: y - size.height, width: width, height: size.height)
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: str.length),
                                                  CGPath(rect: rect, transform: nil), nil)
            ctx.saveGState()
            CTFrameDraw(frame, ctx)
            ctx.restoreGState()
            return size.height
        }

        // ===================== COVER PAGE =====================

        beginPage()

        // Accent bar
        ctx.setFillColor(accentBlue.cgColor)
        ctx.fill(CGRect(x: margin, y: pageHeight - margin - 4, width: usableWidth, height: 4))
        y -= 24

        y -= drawBlock(NSAttributedString(string: conversation.displayName,
                        attributes: [.font: fTitle, .foregroundColor: NSColor.black]),
                        x: margin, width: usableWidth) + 6

        y -= drawBlock(NSAttributedString(string: conversation.isGroupChat ? "Group Conversation" : "Conversation",
                        attributes: [.font: fSubtitle, .foregroundColor: gray50]),
                        x: margin, width: usableWidth) + 20

        // Rule
        ctx.setStrokeColor(NSColor(calibratedWhite: 0.0, alpha: 0.12).cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: margin, y: y))
        ctx.addLine(to: CGPoint(x: margin + usableWidth, y: y))
        ctx.strokePath()
        y -= 16

        let metaItems: [(String, String)] = [
            ("PARTICIPANTS", conversation.participantNames.joined(separator: ", ")),
            ("SERVICE", conversation.serviceName),
            ("MESSAGES", "\(messages.count)"),
            ("DATE RANGE", {
                guard let f = messages.first?.date, let l = messages.last?.date else { return "N/A" }
                return "\(DateFormatting.formatDateOnly(f))  \u{2013}  \(DateFormatting.formatDateOnly(l))"
            }()),
            ("EXPORTED", DateFormatting.formatDateTime(Date()))
        ]

        for (label, value) in metaItems {
            y -= drawBlock(NSAttributedString(string: label, attributes: [.font: fLabel, .foregroundColor: accentBlue]),
                           x: margin, width: usableWidth) + 1
            y -= drawBlock(NSAttributedString(string: value, attributes: [.font: fValue, .foregroundColor: gray15]),
                           x: margin, width: usableWidth) + 10
        }

        endPage()

        // ===================== MESSAGES =====================

        beginPage()
        var prevDate: Date?

        for message in messages {
            guard message.hasContent else { continue }

            // ---- Date separator ----
            if !DateFormatting.isSameDay(message.date, prevDate) {
                ensureSpace(24)
                drawDateSeparator(ctx: ctx, y: &y, date: message.date)
            }
            prevDate = message.date

            // ---- System messages ----
            if message.isSystemMessage || (message.groupTitle != nil && message.groupActionType != 0) {
                let text = (message.groupTitle != nil && message.groupActionType != 0)
                    ? "Group renamed to \"\(message.groupTitle!)\""
                    : (message.text ?? "System event")
                let str = NSAttributedString(string: "\u{25C6}  \(text)",
                                              attributes: [.font: fSystem, .foregroundColor: gray50])
                ensureSpace(14)
                y -= drawBlock(str, x: margin + contentIndent, width: contentWidth) + 6
                continue
            }

            // ---- Outdented timestamp ----
            let timeStr = DateFormatting.formatTimeOnly(message.date)
            let timeAttr = NSAttributedString(string: timeStr, attributes: [.font: fTime, .foregroundColor: gray50])

            // ---- Build message content block ----
            let block = NSMutableAttributedString()

            // Line 1: sender  ·  service  ·  delivered/read status
            let sender = message.isFromMe ? "Me" : message.senderName
            let color = message.isFromMe ? senderMe : senderOther
            block.append(NSAttributedString(string: sender, attributes: [.font: fSender, .foregroundColor: color]))

            if !message.isFromMe && message.senderID != message.senderName {
                block.append(NSAttributedString(string: "  \(message.senderID)", attributes: [.font: fMeta, .foregroundColor: gray65]))
            }

            block.append(NSAttributedString(string: "  \u{00B7}  \(message.service)", attributes: [.font: fMeta, .foregroundColor: gray65]))

            // Delivered / read on the same line
            if message.isFromMe, let d = message.dateDelivered {
                block.append(NSAttributedString(string: "  \u{00B7}  Delivered \(DateFormatting.formatTimeOnly(d))",
                                                 attributes: [.font: fMeta, .foregroundColor: gray65]))
            }
            if let r = message.dateRead {
                block.append(NSAttributedString(string: "  \u{00B7}  Read \(DateFormatting.formatTimeOnly(r))",
                                                 attributes: [.font: fMeta, .foregroundColor: gray65]))
            }

            // Line 2: message body (with extra spacing above)
            if let text = message.text, !text.isEmpty {
                block.append(NSAttributedString(string: "\n", attributes: [.font: fBody, .foregroundColor: gray15]))
                block.append(NSAttributedString(string: text, attributes: [.font: fBody, .foregroundColor: gray15]))
                if message.isEdited {
                    block.append(NSAttributedString(string: "  (edited)", attributes: [.font: fMeta, .foregroundColor: NSColor.orange]))
                }
                if message.isRetracted {
                    block.append(NSAttributedString(string: "  (unsent)", attributes: [.font: fMeta, .foregroundColor: NSColor.red]))
                }
            }

            // Reactions
            if !message.reactions.isEmpty {
                let rText = message.reactions.map { "\($0.emoji) \($0.senderName)" }.joined(separator: "   ")
                block.append(NSAttributedString(string: "\n\(rText)", attributes: [.font: fReaction, .foregroundColor: purple]))
            }

            // Thread
            if let thread = message.threadOriginatorGUID, !thread.isEmpty {
                block.append(NSAttributedString(string: "\n\u{21B3} Reply in thread", attributes: [.font: fMeta, .foregroundColor: accentBlue]))
            }

            // Attachment text labels (for non-image or omitted images)
            for att in message.attachments {
                if att.isImage && attachmentMode == .omit {
                    let name = att.transferName ?? att.filename ?? "image"
                    block.append(NSAttributedString(string: "\n\u{1F5BC}  \(name)  (\(att.formattedSize))",
                                                     attributes: [.font: fMeta, .foregroundColor: gray65]))
                } else if !att.isImage {
                    let name = att.transferName ?? att.filename ?? "file"
                    let icon = attachmentIcon(for: att.mimeType)
                    block.append(NSAttributedString(string: "\n\(icon)  \(name)  (\(att.formattedSize))",
                                                     attributes: [.font: fMeta, .foregroundColor: gray65]))
                }
            }

            // Paragraph style with spacing between lines
            let paraStyle = NSMutableParagraphStyle()
            paraStyle.lineSpacing = 2
            paraStyle.paragraphSpacing = 3
            block.addAttribute(.paragraphStyle, value: paraStyle, range: NSRange(location: 0, length: block.length))

            // Measure the content block
            let setter = CTFramesetterCreateWithAttributedString(block)
            let blockSize = CTFramesetterSuggestFrameSizeWithConstraints(
                setter, CFRange(location: 0, length: block.length), nil,
                CGSize(width: contentWidth, height: .greatestFiniteMagnitude), nil
            )

            ensureSpace(blockSize.height + 8)

            // Draw outdented timestamp at left margin, top-aligned with the content block
            let savedY = y
            _ = drawBlock(timeAttr, x: margin, width: timeWidth)
            y = savedY // restore — timestamp doesn't consume vertical space

            // Draw content block indented
            y -= drawBlock(block, x: margin + contentIndent, width: contentWidth)

            // Draw inline images AFTER the text block
            if attachmentMode != .omit {
                for att in message.attachments where att.isImage {
                    guard let path = att.resolvedPath, let srcImage = NSImage(contentsOfFile: path) else { continue }

                    let img: NSImage
                    if attachmentMode == .thumbnail {
                        img = downsample(srcImage, maxWidth: 640, maxHeight: 480)
                    } else {
                        img = srcImage
                    }

                    let sz = fitSize(img.size, maxWidth: maxImageWidth, maxHeight: maxImageHeight)
                    ensureSpace(sz.height + 18)

                    let imgRect = CGRect(x: margin + contentIndent, y: y - sz.height, width: sz.width, height: sz.height)

                    ctx.setStrokeColor(ruleColor.cgColor)
                    ctx.setLineWidth(0.5)
                    ctx.stroke(imgRect.insetBy(dx: -1, dy: -1))

                    if let cgImg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                        ctx.draw(cgImg, in: imgRect)
                    }
                    y -= sz.height + 3

                    let name = att.transferName ?? "image"
                    y -= drawBlock(NSAttributedString(string: "\(name)  \u{00B7}  \(att.formattedSize)",
                                                       attributes: [.font: fMeta, .foregroundColor: gray65]),
                                   x: margin + contentIndent, width: contentWidth) + 2
                }
            }

            y -= 8 // spacing between messages
        }

        endPage()
        ctx.closePDF()
    }

    // MARK: - Date Separator

    private static func drawDateSeparator(ctx: CGContext, y: inout CGFloat, date: Date?) {
        let text = DateFormatting.formatDateOnly(date)
        let attrStr = NSAttributedString(string: text, attributes: [.font: fDateSep, .foregroundColor: NSColor(calibratedWhite: 0.40, alpha: 1.0)])
        let size = attrStr.size()
        let center = margin + usableWidth / 2
        let lineY = y - size.height / 2

        ctx.setStrokeColor(ruleColor.cgColor)
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: margin, y: lineY))
        ctx.addLine(to: CGPoint(x: center - size.width / 2 - 12, y: lineY))
        ctx.strokePath()
        ctx.move(to: CGPoint(x: center + size.width / 2 + 12, y: lineY))
        ctx.addLine(to: CGPoint(x: margin + usableWidth, y: lineY))
        ctx.strokePath()

        let setter = CTFramesetterCreateWithAttributedString(attrStr)
        let rect = CGRect(x: center - size.width / 2, y: y - size.height, width: size.width + 2, height: size.height)
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: attrStr.length),
                                              CGPath(rect: rect, transform: nil), nil)
        ctx.saveGState()
        CTFrameDraw(frame, ctx)
        ctx.restoreGState()

        y -= size.height + 12
    }

    // MARK: - Footer

    private static func drawFooter(ctx: CGContext, page: Int, name: String) {
        let ruleY = margin - 8
        ctx.setStrokeColor(ruleColor.cgColor)
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: margin, y: ruleY))
        ctx.addLine(to: CGPoint(x: margin + usableWidth, y: ruleY))
        ctx.strokePath()

        let footerY = margin - 22.0

        // Left: conversation name
        let left = NSAttributedString(string: name, attributes: [.font: fFooter, .foregroundColor: gray50])
        let lSetter = CTFramesetterCreateWithAttributedString(left)
        let lSize = CTFramesetterSuggestFrameSizeWithConstraints(lSetter, CFRange(location: 0, length: left.length), nil, CGSize(width: usableWidth / 2, height: 20), nil)
        let lFrame = CTFramesetterCreateFrame(lSetter, CFRange(location: 0, length: left.length),
            CGPath(rect: CGRect(x: margin, y: footerY, width: usableWidth / 2, height: lSize.height), transform: nil), nil)
        ctx.saveGState(); CTFrameDraw(lFrame, ctx); ctx.restoreGState()

        // Right: page number
        let right = NSAttributedString(string: "Page \(page)", attributes: [.font: fFooter, .foregroundColor: gray50])
        let rSize = right.size()
        let rSetter = CTFramesetterCreateWithAttributedString(right)
        let rFrame = CTFramesetterCreateFrame(rSetter, CFRange(location: 0, length: right.length),
            CGPath(rect: CGRect(x: margin + usableWidth - rSize.width - 2, y: footerY, width: rSize.width + 2, height: rSize.height), transform: nil), nil)
        ctx.saveGState(); CTFrameDraw(rFrame, ctx); ctx.restoreGState()
    }

    // MARK: - Helpers

    private static func downsample(_ image: NSImage, maxWidth: CGFloat, maxHeight: CGFloat) -> NSImage {
        let s = image.size
        guard s.width > maxWidth || s.height > maxHeight else { return image }
        let ratio = min(maxWidth / s.width, maxHeight / s.height)
        let newSize = CGSize(width: s.width * ratio, height: s.height * ratio)
        let img = NSImage(size: newSize)
        img.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: CGRect(origin: .zero, size: newSize), from: CGRect(origin: .zero, size: s), operation: .copy, fraction: 1.0)
        img.unlockFocus()
        return img
    }

    private static func fitSize(_ original: CGSize, maxWidth: CGFloat, maxHeight: CGFloat) -> CGSize {
        guard original.width > 0, original.height > 0 else { return CGSize(width: 100, height: 100) }
        let ratio = min(maxWidth / original.width, maxHeight / original.height, 1.0)
        return CGSize(width: original.width * ratio, height: original.height * ratio)
    }

    private static func attachmentIcon(for mimeType: String?) -> String {
        guard let m = mimeType else { return "\u{1F4CE}" }
        if m.hasPrefix("video/") { return "\u{1F3AC}" }
        if m.hasPrefix("audio/") { return "\u{1F3B5}" }
        if m.contains("pdf") { return "\u{1F4C4}" }
        return "\u{1F4CE}"
    }

    enum ExportError: LocalizedError {
        case cannotCreatePDF
        var errorDescription: String? { "Could not create PDF context" }
    }
}
