import Foundation

protocol NotionSyncScheduling: Sendable {
    func enqueue(messageID: UUID)
}

struct ChatSessionSettings: Sendable {
    var modelID: String
    var supportsVision: Bool
    var systemPrompt: String?

    init(modelID: String, supportsVision: Bool, systemPrompt: String? = nil) {
        self.modelID = modelID
        self.supportsVision = supportsVision
        self.systemPrompt = systemPrompt
    }
}

enum ChatSessionBlockReason: Equatable, Sendable {
    case unsupportedVision
}

enum ChatSessionState: Equatable, Sendable {
    case idle
    case generating(text: String)
    case stopped(text: String?)
    case failed(message: String)
    case blocked(ChatSessionBlockReason)
}

struct ChatDraft: Equatable {
    let text: String
    let attachments: [MessageAttachment]
}
