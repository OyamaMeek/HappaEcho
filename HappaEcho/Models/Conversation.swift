import Foundation
import SwiftData

/// A chat conversation and the records it owns.
@Model
final class Conversation {
    /// Stable identity used by controllers and Notion markers.
    @Attribute(.unique) var id: UUID

    /// Display title; starts as "新对话" and later becomes model-generated or
    /// manually edited.
    var title: String

    var createdAt: Date
    var updatedAt: Date

    /// Model identifier in effect for this conversation.
    var modelID: String?

    /// True once the user edits the title; model-generated titles must never
    /// overwrite it.
    var isTitleManuallyEdited: Bool

    /// Persisted title-generation-attempt flag. Set only when a model title
    /// request actually starts, so each conversation attempts at most once.
    var titleGenerationAttempted: Bool

    /// True while a stream for this conversation is in flight (single active
    /// generation per conversation).
    var isGenerating: Bool

    // MARK: Notion checkpoint fields

    var notionLastSyncAt: Date?
    var notionSyncError: String?

    @Relationship(deleteRule: .cascade, inverse: \Message.conversation)
    var messages: [Message] = []

    @Relationship(deleteRule: .cascade, inverse: \NotionPageBinding.conversation)
    var pageBindings: [NotionPageBinding] = []

    init(
        id: UUID = UUID(),
        title: String = "新对话",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        modelID: String? = nil,
        isTitleManuallyEdited: Bool = false,
        titleGenerationAttempted: Bool = false,
        isGenerating: Bool = false,
        notionLastSyncAt: Date? = nil,
        notionSyncError: String? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.modelID = modelID
        self.isTitleManuallyEdited = isTitleManuallyEdited
        self.titleGenerationAttempted = titleGenerationAttempted
        self.isGenerating = isGenerating
        self.notionLastSyncAt = notionLastSyncAt
        self.notionSyncError = notionSyncError
    }
}

extension Conversation {
    /// Messages in explicit `sequence` order — the persisted ordering contract
    /// consumed by context building.
    var sortedMessages: [Message] {
        messages.sorted { $0.sequence < $1.sequence }
    }

    /// The single binding currently flagged as current. Returns the newest one
    /// if the invariant is ever violated.
    var activePageBinding: NotionPageBinding? {
        pageBindings.filter(\.isCurrent).max { $0.createdAt < $1.createdAt }
    }

    /// Retires any current binding and creates a fresh one, preserving prior
    /// bindings as history for diagnostics when the database changes.
    @discardableResult
    func bindNotionPage(databaseID: String, pageID: String, at date: Date = .now) -> NotionPageBinding {
        for binding in pageBindings where binding.isCurrent {
            binding.isCurrent = false
        }
        let binding = NotionPageBinding(databaseID: databaseID, pageID: pageID, createdAt: date)
        binding.isCurrent = true
        binding.conversation = self
        pageBindings.append(binding)
        return binding
    }
}
