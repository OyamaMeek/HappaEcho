import Foundation

protocol NotionSyncScheduling: Sendable {
    func enqueue(messageID: UUID)
    func cancel(conversationID: UUID)
}

extension NotionSyncScheduling {
    func enqueueMetadata(conversationID: UUID) {}
    func resumePending() {}
}

final class NotionSyncScheduler: NotionSyncScheduling, @unchecked Sendable {
    private let coordinator: NotionSyncCoordinator

    init(coordinator: NotionSyncCoordinator) {
        self.coordinator = coordinator
    }

    func enqueue(messageID: UUID) {
        Task { await coordinator.enqueue(messageID: messageID) }
    }

    func enqueueMetadata(conversationID: UUID) {
        Task { await coordinator.enqueueMetadata(conversationID: conversationID) }
    }

    func resumePending() {
        Task { await coordinator.resumePending() }
    }

    func cancel(conversationID: UUID) {
        Task { await coordinator.cancel(conversationID: conversationID) }
    }
}
