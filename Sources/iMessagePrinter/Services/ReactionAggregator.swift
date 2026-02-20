import Foundation

enum ReactionAggregator {
    /// Groups reaction messages onto their target messages
    /// Returns: (cleanMessages: non-reaction messages with reactions attached, handleMap used for sender names)
    static func aggregate(
        messages: [MessageRecord],
        handleMap: [Int64: HandleRecord],
        contactResolver: ContactResolver
    ) -> [MessageRecord: [Reaction]] {
        // Build a lookup from GUID → reactions
        var reactionsByGUID: [String: [ReactionEntry]] = [:]

        for msg in messages where msg.isReaction || msg.isReactionRemoval {
            guard let targetGUID = msg.targetMessageGUID,
                  let emoji = msg.reactionType else { continue }

            let senderName: String
            if msg.isFromMe {
                senderName = "Me"
            } else if let handle = handleMap[msg.handleID] {
                senderName = contactResolver.displayName(for: handle.id)
            } else {
                senderName = "Unknown"
            }

            let entry = ReactionEntry(
                emoji: emoji,
                senderName: senderName,
                isRemoval: msg.isReactionRemoval
            )

            reactionsByGUID[targetGUID, default: []].append(entry)
        }

        // Resolve reactions: apply additions and removals
        var result: [String: [Reaction]] = [:]
        for (guid, entries) in reactionsByGUID {
            var active: [String: Set<String>] = [:] // emoji → set of sender names
            for entry in entries {
                if entry.isRemoval {
                    active[entry.emoji]?.remove(entry.senderName)
                } else {
                    active[entry.emoji, default: []].insert(entry.senderName)
                }
            }
            var reactions: [Reaction] = []
            for (emoji, senders) in active.sorted(by: { $0.key < $1.key }) {
                for sender in senders.sorted() {
                    reactions.append(Reaction(emoji: emoji, senderName: sender))
                }
            }
            if !reactions.isEmpty {
                result[guid] = reactions
            }
        }

        // Build the final map keyed by MessageRecord
        var messageReactions: [MessageRecord: [Reaction]] = [:]
        for msg in messages where !msg.isReaction && !msg.isReactionRemoval {
            if let reactions = result[msg.guid] {
                messageReactions[msg] = reactions
            }
        }

        return messageReactions
    }
}

private struct ReactionEntry {
    let emoji: String
    let senderName: String
    let isRemoval: Bool
}

// Make MessageRecord hashable for use as dictionary key
extension MessageRecord: Hashable {
    static func == (lhs: MessageRecord, rhs: MessageRecord) -> Bool {
        lhs.rowID == rhs.rowID
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(rowID)
    }
}
