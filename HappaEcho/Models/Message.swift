import Foundation
import SwiftData

/// A single persisted turn in a conversation.
@Model
final class Message {
    /// Stable identity used by controllers and Notion block markers.
    @Attribute(.unique) var id: UUID

    var role: MessageRole
    var content: String
    var createdAt: Date

    /// Explicit integer ordering within the conversation.
    var sequence: Int

    /// Terminal assistant stream outcome; `.none` for user messages.
    var generationState: GenerationState

    // MARK: Notion checkpoint fields

    var syncState: SyncState
    var syncError: String?
    var lastSyncedAt: Date?
    var lastConfirmedAt: Date?

    /// Zero-based cursor for the next deterministic batch to append.
    var nextNotionBatchIndex: Int

    /// Serialized indices of batches whose blocks were confirmed on the page.
    var confirmedBatchIDs: [String]

    /// Serialized remote block IDs for each confirmed batch, in batch order.
    var confirmedBlockIDs: [String]

    var conversation: Conversation?

    @Relationship(deleteRule: .cascade, inverse: \MessageAttachment.message)
    var attachments: [MessageAttachment] = []

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        createdAt: Date = .now,
        sequence: Int,
        generationState: GenerationState = .none,
        syncState: SyncState = .pending,
        syncError: String? = nil,
        lastSyncedAt: Date? = nil,
        lastConfirmedAt: Date? = nil,
        nextNotionBatchIndex: Int = 0,
        confirmedBatchIDs: [String] = [],
        confirmedBlockIDs: [String] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.sequence = sequence
        self.generationState = generationState
        self.syncState = syncState
        self.syncError = syncError
        self.lastSyncedAt = lastSyncedAt
        self.lastConfirmedAt = lastConfirmedAt
        self.nextNotionBatchIndex = nextNotionBatchIndex
        self.confirmedBatchIDs = confirmedBatchIDs
        self.confirmedBlockIDs = confirmedBlockIDs
    }
}

extension Message {
    /// Records a confirmed batch. Array fields are replaced copy-on-write so
    /// SwiftData observes the mutation and persists the advanced cursor and the
    /// remote IDs in the same save.
    func confirmBatch(index: Int, blockIDs: [String], at date: Date = .now) {
        nextNotionBatchIndex = max(nextNotionBatchIndex, index + 1)
        confirmedBatchIDs = confirmedBatchIDs + [String(index)]
        confirmedBlockIDs = confirmedBlockIDs + blockIDs
        lastConfirmedAt = date
    }
}
