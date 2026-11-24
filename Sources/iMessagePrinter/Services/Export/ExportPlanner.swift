import Foundation

struct ExportPlanner {
    let db: DatabaseService
    let handleMap: [Int64: HandleRecord]
    let contactResolver: ContactResolver

    init(db: DatabaseService, handleMap: [Int64: HandleRecord], contactResolver: ContactResolver) {
        self.db = db
        self.handleMap = handleMap
        self.contactResolver = contactResolver
    }

    func plan(
        conversation: ConversationInfo,
        imageMode: ExportImageMode,
        progress: @escaping (ExportProgress) -> Void,
        isCancelled: @escaping () -> Bool
    ) throws -> ExportConversation {
        let records = try db.fetchMessages(chatRowID: conversation.chatRowID)
        let reactionMap = ReactionAggregator.aggregate(
            messages: records,
            handleMap: handleMap,
            contactResolver: contactResolver
        )
        let attachmentsByMessage = try db.fetchAttachments(chatRowID: conversation.chatRowID)
        let messageRecords = records.filter { !$0.isReaction && !$0.isReactionRemoval }

        var estimator = ExportProgressEstimator(
            totalMessages: messageRecords.count,
            totalImages: 0
        )
        estimator.setPhase(.preparing)

        var messages: [ExportMessage] = []
        messages.reserveCapacity(messageRecords.count)

        for record in messageRecords {
            if isCancelled() {
                throw CancellationError()
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
            } else if let handle = handleMap[record.handleID] {
                senderID = handle.id
                senderName = contactResolver.displayName(for: handle.id)
            } else {
                senderID = "Unknown"
                senderName = "Unknown"
            }

            let attachments = (attachmentsByMessage[record.rowID] ?? []).map { attachment in
                ExportAttachment(
                    id: attachment.rowID,
                    filename: attachment.filename,
                    transferName: attachment.transferName,
                    mimeType: attachment.mimeType,
                    totalBytes: attachment.totalBytes,
                    isImage: attachment.isImage,
                    resolvedPath: attachment.resolvedPath,
                    formattedSize: attachment.formattedSize
                )
            }

            messages.append(ExportMessage(
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
                reactions: reactionMap[record] ?? [],
                attachments: attachments
            ))

            estimator.messageCompleted()
            if messages.count % 250 == 0 {
                progress(estimator.snapshot)
            }
        }

        progress(estimator.snapshot)

        return ExportConversation(
            chatRowID: conversation.chatRowID,
            chatGUID: conversation.chatGUID,
            displayName: conversation.displayName,
            participants: conversation.participants,
            participantNames: conversation.participantNames,
            serviceName: conversation.serviceName,
            isGroupChat: conversation.isGroupChat,
            messages: messages
        )
    }
}

final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}
