import SwiftUI

struct MessageRowView: View {
    let message: DisplayMessage

    private var senderColor: Color {
        message.isFromMe ? .green : .blue
    }

    var body: some View {
        if message.isSystemMessage || (message.groupTitle != nil && message.groupActionType != 0) {
            systemRow
        } else {
            messageRow
        }
    }

    // MARK: - System message

    private var systemRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)

            let text = (message.groupTitle != nil && message.groupActionType != 0)
                ? "Group renamed to \"\(message.groupTitle!)\""
                : (message.text ?? "System event")

            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .italic()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Regular message

    private var messageRow: some View {
        HStack(alignment: .top, spacing: 0) {
            // Outdented timestamp
            Text(DateFormatting.formatTimeOnly(message.date))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(width: 52, alignment: .leading)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                // Sender line with metadata
                senderLine
                    .textSelection(.enabled)

                // Message body
                if let text = message.text, !text.isEmpty {
                    HStack(spacing: 4) {
                        Text(text)
                            .font(.body)
                            .textSelection(.enabled)

                        if message.isEdited {
                            Text("edited")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
                        }
                        if message.isRetracted {
                            Text("unsent")
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
                        }
                    }
                }

                // Reactions
                if !message.reactions.isEmpty {
                    reactionsView
                }

                // Thread
                if let _ = message.threadOriginatorGUID {
                    Label("Reply in thread", systemImage: "arrowshape.turn.up.left")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }

                // Attachments
                if !message.attachments.isEmpty {
                    attachmentsView
                }
            }
        }
        .padding(.vertical, 5)
    }

    // MARK: - Sender line

    private var senderLine: some View {
        HStack(spacing: 0) {
            Text(message.isFromMe ? "Me" : message.senderName)
                .font(.callout.weight(.semibold))
                .foregroundStyle(senderColor)

            if !message.isFromMe && message.senderID != message.senderName {
                Text("  \(message.senderID)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text("  \u{00B7}  ")
                .foregroundStyle(.quaternary)
            Text(message.service)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if message.isFromMe, let d = message.dateDelivered {
                Text("  \u{00B7}  Delivered \(DateFormatting.formatTimeOnly(d))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if let r = message.dateRead {
                Text("  \u{00B7}  Read \(DateFormatting.formatTimeOnly(r))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Reactions

    private var reactionsView: some View {
        HStack(spacing: 6) {
            ForEach(Array(message.reactions.enumerated()), id: \.offset) { _, reaction in
                HStack(spacing: 2) {
                    Text(reaction.emoji)
                        .font(.caption)
                    Text(reaction.senderName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.purple.opacity(0.08), in: Capsule())
            }
        }
    }

    // MARK: - Attachments

    @ViewBuilder
    private var attachmentsView: some View {
        ForEach(message.attachments) { attachment in
            if attachment.isImage, let image = attachment.image {
                VStack(alignment: .leading, spacing: 3) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 280, maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(.separator, lineWidth: 0.5)
                        )

                    Text("\(attachment.transferName ?? "image")  \u{00B7}  \(attachment.formattedSize)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: attachmentIcon(attachment))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(attachment.transferName ?? attachment.filename ?? "file")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(attachment.formattedSize)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func attachmentIcon(_ att: DisplayAttachment) -> String {
        guard let mime = att.mimeType else { return "paperclip" }
        if mime.hasPrefix("video/") { return "film" }
        if mime.hasPrefix("audio/") { return "music.note" }
        if mime.contains("pdf") { return "doc.richtext" }
        return "paperclip"
    }
}
