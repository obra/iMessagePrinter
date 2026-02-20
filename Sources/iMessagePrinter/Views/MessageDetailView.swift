import SwiftUI

struct MessageDetailView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if let conversation = appState.selectedConversation {
                VStack(spacing: 0) {
                    headerView(conversation)
                        .padding()
                        .background(.bar)

                    Divider()

                    // Messages area
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
                                        let prevMessage = index > 0 ? appState.messages[index - 1] : nil

                                        if !DateFormatting.isSameDay(message.date, prevMessage?.date) {
                                            DateSeparatorView(date: message.date)
                                        }

                                        MessageRowView(message: message)
                                    }
                                }
                                .padding()
                            }

                            // Progress pill while streaming
                            if appState.isLoadingMessages {
                                loadingOverlay
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                    }
                }
                .overlay {
                    // Export overlay
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
        VStack(alignment: .leading, spacing: 4) {
            Text(conversation.displayName)
                .font(.title2)
                .fontWeight(.semibold)

            HStack(spacing: 12) {
                Label("\(appState.messages.count) messages", systemImage: "message")
                Label(conversation.serviceName, systemImage: "network")

                if conversation.isGroupChat {
                    Label("\(conversation.participants.count) participants", systemImage: "person.3")
                }

                if let first = appState.messages.first?.date,
                   let last = appState.messages.last?.date {
                    Label(
                        "\(DateFormatting.formatDateOnly(first)) - \(DateFormatting.formatDateOnly(last))",
                        systemImage: "calendar"
                    )
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if conversation.isGroupChat && !conversation.participantNames.isEmpty {
                Text("Participants: \(conversation.participantNames.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
