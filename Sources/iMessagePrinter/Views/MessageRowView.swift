import SwiftUI

struct MessageRowView: View {
    let message: DisplayMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Main message line
            Text(message.formattedLogLine)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)

            // Metadata
            metadataView
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.leading, 24)

            // Reactions
            if !message.reactions.isEmpty {
                reactionsView
                    .padding(.leading, 24)
            }

            // Attachments
            if !message.attachments.isEmpty {
                attachmentsView
                    .padding(.leading, 24)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var metadataView: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let delivered = message.dateDelivered, message.isFromMe {
                Text("Delivered: \(DateFormatting.formatDateTime(delivered))")
            }
            if let read = message.dateRead {
                Text("Read: \(DateFormatting.formatDateTime(read))")
            }
            if message.isEdited {
                Text("(edited)")
                    .foregroundStyle(.orange)
            }
            if message.isRetracted {
                Text("(unsent)")
                    .foregroundStyle(.red)
            }
            if let thread = message.threadOriginatorGUID {
                Text("Thread reply to: \(thread.prefix(12))...")
                    .foregroundStyle(.blue)
            }
        }
    }

    private var reactionsView: some View {
        let reactionText = message.reactions
            .map { "\($0.emoji) \($0.senderName)" }
            .joined(separator: ", ")
        return Text("Reactions: \(reactionText)")
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.purple)
    }

    @ViewBuilder
    private var attachmentsView: some View {
        ForEach(message.attachments) { attachment in
            if attachment.isImage, let image = attachment.image {
                VStack(alignment: .leading, spacing: 2) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 300, maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    Text("[Image: \(attachment.transferName ?? "image") (\(attachment.formattedSize))]")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("[Attachment: \(attachment.transferName ?? attachment.filename ?? "file") (\(attachment.formattedSize))]")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
