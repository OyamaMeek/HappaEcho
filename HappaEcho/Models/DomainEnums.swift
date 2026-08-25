import Foundation

/// The speaker of a persisted message.
enum MessageRole: String, Codable {
    case user
    case assistant
}

/// Lifecycle of an assistant response relative to its streaming request.
///
/// `completed`, `stopped`, and `failedPartial` are the terminal states Task 6
/// persists to the store; `none` is the placeholder used before any generation
/// runs (and for user messages); `generating` and `failed` describe transient
/// drafts that never reach the store.
enum GenerationState: String, Codable {
    case none
    case generating
    case completed
    case stopped
    case failedPartial
    case failed
}

/// Notion backup status for a single message. Every newly created message
/// begins `.pending`; disabling Notion pauses execution but never changes this
/// state.
enum SyncState: String, Codable {
    case pending
    case syncing
    case synced
    case failed
}
