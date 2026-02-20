import SwiftUI

struct ConversationRowView: View {
    let conversation: ConversationInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(conversation.displayName)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                if let date = conversation.lastMessageDate {
                    Text(DateFormatting.formatDateOnly(date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                if let preview = conversation.lastMessagePreview {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Text("\(conversation.messageCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }

            HStack(spacing: 4) {
                if conversation.isGroupChat {
                    Image(systemName: "person.3.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(conversation.serviceName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
