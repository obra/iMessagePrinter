import Foundation
import AppKit

@Observable
final class AppState {
    var hasFullDiskAccess = false
    var conversations: [ConversationInfo] = []
    var selectedConversation: ConversationInfo?
    var messages: [DisplayMessage] = []
    var searchText = ""
    var isLoadingConversations = false
    var isLoadingMessages = false
    var isExportingPDF = false
    var errorMessage: String?
    var loadedMessageCount = 0
    var totalMessageCount = 0
    var loadedConversationCount = 0
    var totalConversationCount = 0

    private var databaseService: DatabaseService?
    private var contactResolver = ContactResolver()
    private var handleMap: [Int64: HandleRecord] = [:]
    private var messageLoadTask: Task<Void, Never>?

    var filteredConversations: [ConversationInfo] {
        if searchText.isEmpty { return conversations }
        let query = searchText.lowercased()
        return conversations.filter { conv in
            conv.displayName.lowercased().contains(query)
            || conv.participants.contains { $0.lowercased().contains(query) }
            || conv.participantNames.contains { $0.lowercased().contains(query) }
            || (conv.lastMessagePreview?.lowercased().contains(query) ?? false)
        }
    }

    func checkAccess() {
        hasFullDiskAccess = FullDiskAccessChecker.hasAccess
    }

    func loadConversations() {
        guard hasFullDiskAccess else { return }
        isLoadingConversations = true
        errorMessage = nil
        conversations = []
        loadedConversationCount = 0
        totalConversationCount = 0

        Task.detached { [self] in
            do {
                let db = try DatabaseService()
                let handles = try db.fetchAllHandles()

                // Await contact access BEFORE resolving any names
                await self.contactResolver.ensureAccess()

                await MainActor.run {
                    self.databaseService = db
                    self.handleMap = handles
                }

                let rawConversations = try db.fetchConversations()

                await MainActor.run {
                    self.totalConversationCount = rawConversations.count
                }

                let batchSize = 50
                var batch: [ConversationInfo] = []

                for (index, raw) in rawConversations.enumerated() {
                    let chatHandles = try db.fetchHandlesForChat(chatRowID: raw.rowID)
                    let participants = chatHandles.map(\.id)
                    let participantNames = chatHandles.map { self.contactResolver.displayName(for: $0.id) }

                    let displayName: String
                    if let name = raw.displayName, !name.isEmpty {
                        displayName = name
                    } else if participantNames.count == 1 {
                        displayName = participantNames[0]
                    } else if !participantNames.isEmpty {
                        displayName = participantNames.joined(separator: ", ")
                    } else {
                        displayName = raw.chatIdentifier ?? "Unknown"
                    }

                    let preview = try db.fetchLastMessagePreview(chatRowID: raw.rowID)

                    batch.append(ConversationInfo(
                        chatRowID: raw.rowID,
                        chatGUID: raw.guid,
                        displayName: displayName,
                        participants: participants,
                        participantNames: participantNames,
                        messageCount: raw.messageCount,
                        lastMessageDate: DateFormatting.dateFromAppleTimestamp(raw.lastMessageDate),
                        lastMessagePreview: preview,
                        isGroupChat: raw.style == 43,
                        serviceName: raw.serviceName ?? "iMessage"
                    ))

                    if batch.count >= batchSize {
                        let toAppend = batch
                        let count = index + 1
                        await MainActor.run {
                            self.conversations.append(contentsOf: toAppend)
                            self.loadedConversationCount = count
                        }
                        batch = []
                    }
                }

                // Flush remaining
                if !batch.isEmpty {
                    let toAppend = batch
                    await MainActor.run {
                        self.conversations.append(contentsOf: toAppend)
                    }
                }

                await MainActor.run {
                    self.loadedConversationCount = self.conversations.count
                    self.isLoadingConversations = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to load conversations: \(error.localizedDescription)"
                    self.isLoadingConversations = false
                }
            }
        }
    }

    func loadMessages(for conversation: ConversationInfo) {
        guard let db = databaseService else { return }

        // Cancel any in-flight message load
        messageLoadTask?.cancel()

        selectedConversation = conversation
        isLoadingMessages = true
        messages = []
        loadedMessageCount = 0
        totalMessageCount = 0

        let chatRowID = conversation.chatRowID

        messageLoadTask = Task.detached { [self] in
            do {
                let records = try db.fetchMessages(chatRowID: chatRowID)

                try Task.checkCancellation()

                await MainActor.run {
                    self.totalMessageCount = records.count
                }

                // Aggregate reactions
                let reactionMap = ReactionAggregator.aggregate(
                    messages: records,
                    handleMap: self.handleMap,
                    contactResolver: self.contactResolver
                )

                // Stream messages in batches for progressive display
                let batchSize = 200
                var batch: [DisplayMessage] = []
                var processed = 0

                for record in records {
                    try Task.checkCancellation()

                    guard !record.isReaction && !record.isReactionRemoval else {
                        processed += 1
                        continue
                    }

                    var text = record.text
                    if (text == nil || text?.isEmpty == true), let blob = record.attributedBody {
                        text = AttributedBodyParser.extractText(from: blob)
                    }

                    let senderID: String
                    let senderName: String
                    if record.isFromMe {
                        senderID = "Me"
                        senderName = "Me"
                    } else if let handle = self.handleMap[record.handleID] {
                        senderID = handle.id
                        senderName = self.contactResolver.displayName(for: handle.id)
                    } else {
                        senderID = "Unknown"
                        senderName = "Unknown"
                    }

                    var displayAttachments: [DisplayAttachment] = []
                    if record.cacheHasAttachments {
                        let attachments = try db.fetchAttachments(messageRowID: record.rowID)
                        for att in attachments {
                            var image: NSImage?
                            if att.isImage, let path = att.resolvedPath, att.isDownloaded {
                                image = NSImage(contentsOfFile: path)
                            }
                            displayAttachments.append(DisplayAttachment(
                                id: att.rowID,
                                filename: att.filename,
                                transferName: att.transferName,
                                mimeType: att.mimeType,
                                totalBytes: att.totalBytes,
                                isImage: att.isImage,
                                resolvedPath: att.resolvedPath,
                                formattedSize: att.formattedSize,
                                image: image
                            ))
                        }
                    }

                    let reactions = reactionMap[record] ?? []

                    let msg = DisplayMessage(
                        id: record.rowID,
                        guid: record.guid,
                        text: text,
                        senderName: senderName,
                        senderID: senderID,
                        isFromMe: record.isFromMe,
                        date: DateFormatting.dateFromAppleTimestamp(record.date),
                        dateRead: DateFormatting.dateFromAppleTimestamp(record.dateRead),
                        dateDelivered: DateFormatting.dateFromAppleTimestamp(record.dateDelivered),
                        service: record.service ?? "iMessage",
                        isDelivered: record.isDelivered,
                        isRead: record.isRead,
                        isSent: record.isSent,
                        isSystemMessage: record.isSystemMessage,
                        isEdited: record.dateEdited != nil && record.dateEdited! > 0,
                        isRetracted: record.dateRetracted != nil && record.dateRetracted! > 0,
                        replyToGUID: record.replyToGUID,
                        threadOriginatorGUID: record.threadOriginatorGUID,
                        groupTitle: record.groupTitle,
                        groupActionType: record.groupActionType,
                        reactions: reactions,
                        attachments: displayAttachments
                    )

                    batch.append(msg)
                    processed += 1

                    // Flush batch to UI
                    if batch.count >= batchSize {
                        let toAppend = batch
                        let count = processed
                        await MainActor.run {
                            self.messages.append(contentsOf: toAppend)
                            self.loadedMessageCount = count
                        }
                        batch = []
                    }
                }

                try Task.checkCancellation()

                // Flush remaining
                if !batch.isEmpty {
                    let toAppend = batch
                    await MainActor.run {
                        self.messages.append(contentsOf: toAppend)
                    }
                }

                await MainActor.run {
                    self.loadedMessageCount = self.messages.count
                    self.isLoadingMessages = false
                }
            } catch is CancellationError {
                // Silently stop — a new load replaced us
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to load messages: \(error.localizedDescription)"
                    self.isLoadingMessages = false
                }
            }
        }
    }

    func exportPDF() {
        guard let conversation = selectedConversation, !messages.isEmpty else { return }
        isExportingPDF = true

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(conversation.displayName) - Messages.pdf"

        // Accessory view with attachment options
        let accessory = ExportAccessoryView()
        panel.accessoryView = accessory

        guard panel.runModal() == .OK, let url = panel.url else {
            isExportingPDF = false
            return
        }

        let attachmentMode = accessory.selectedMode

        Task.detached { [self] in
            do {
                try PDFExportService.export(
                    conversation: conversation,
                    messages: self.messages,
                    attachmentMode: attachmentMode,
                    to: url
                )
                await MainActor.run {
                    self.isExportingPDF = false
                    NSWorkspace.shared.open(url)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "PDF export failed: \(error.localizedDescription)"
                    self.isExportingPDF = false
                }
            }
        }
    }
}
