import SwiftUI

struct ConversationRowView: View {
    let conversation: ConversationInfo

    var body: some View {
        HStack(spacing: 10) {
            // Avatar circle
            ZStack {
                Circle()
                    .fill(conversation.isGroupChat ? .blue.opacity(0.15) : .green.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: conversation.isGroupChat ? "person.3.fill" : "person.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(conversation.isGroupChat ? .blue : .green)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(conversation.displayName)
                        .font(.body.weight(.medium))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if let date = conversation.lastMessageDate {
                        Text(shortDate(date))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                HStack {
                    if let preview = conversation.lastMessagePreview {
                        Text(preview)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    HStack(spacing: 4) {
                        Text("\(conversation.messageCount)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)

                        Text(conversation.serviceName)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func shortDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return DateFormatting.formatTimeOnly(date)
        } else if cal.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            return DateFormatting.formatDateOnly(date)
        }
    }
}
