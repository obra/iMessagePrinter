import SwiftUI

struct MessageDetailView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if let conversation = appState.selectedConversation {
                VStack(spacing: 0) {
                    headerView(conversation)

                    Divider()

                    if appState.messages.isEmpty && appState.isLoadingMessages {
                        VStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.large)
                            Text("Loading messages...")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if appState.messages.isEmpty && !appState.isLoadingMessages {
                        ContentUnavailableView(
                            "No Messages",
                            systemImage: "text.bubble",
                            description: Text("This conversation has no messages.")
                        )
                    } else {
                        ZStack(alignment: .bottom) {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    ForEach(Array(appState.messages.enumerated()), id: \.element.id) { index, message in
                                        let prev = index > 0 ? appState.messages[index - 1] : nil

                                        if !DateFormatting.isSameDay(message.date, prev?.date) {
                                            DateSeparatorView(date: message.date)
                                        }

                                        MessageRowView(message: message)

                                        // Thin separator between messages from different senders
                                        if let next = index + 1 < appState.messages.count ? appState.messages[index + 1] : nil,
                                           next.isFromMe != message.isFromMe {
                                            Divider()
                                                .padding(.leading, 52)
                                                .padding(.vertical, 2)
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            }

                            if appState.isLoadingMessages {
                                loadingOverlay
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                    }
                }
                .overlay {
                    if appState.isExportingPDF {
                        exportingOverlay
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            appState.exportPDF()
                        } label: {
                            Label("Export PDF", systemImage: "arrow.down.doc")
                        }
                        .disabled(appState.messages.isEmpty || appState.isExportingPDF || appState.isLoadingMessages)
                    }
                }
            } else {
                ContentUnavailableView(
                    "Select a Conversation",
                    systemImage: "message",
                    description: Text("Choose a conversation from the sidebar to view messages.")
                )
            }
        }
    }

    private var loadingOverlay: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Loading messages... \(appState.loadedMessageCount) / \(appState.totalMessageCount)")
                .font(.callout)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .padding(.bottom, 12)
    }

    private var exportingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Exporting PDF...")
                .font(.headline)
            Text("\(appState.messages.count) messages")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func headerView(_ conversation: ConversationInfo) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(conversation.isGroupChat ? .blue.opacity(0.12) : .green.opacity(0.12))
                        .frame(width: 42, height: 42)
                    Image(systemName: conversation.isGroupChat ? "person.3.fill" : "person.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(conversation.isGroupChat ? .blue : .green)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(conversation.displayName)
                        .font(.title3.weight(.semibold))

                    HStack(spacing: 8) {
                        Label("\(appState.messages.count)", systemImage: "message")
                        Label(conversation.serviceName, systemImage: "network")

                        if conversation.isGroupChat {
                            Label("\(conversation.participants.count)", systemImage: "person.3")
                        }

                        if let first = appState.messages.first?.date,
                           let last = appState.messages.last?.date {
                            Label(
                                "\(DateFormatting.formatDateOnly(first)) \u{2013} \(DateFormatting.formatDateOnly(last))",
                                systemImage: "calendar"
                            )
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if conversation.isGroupChat && !conversation.participantNames.isEmpty {
                HStack {
                    Text(conversation.participantNames.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
        }
        .background(.bar)
    }
}
