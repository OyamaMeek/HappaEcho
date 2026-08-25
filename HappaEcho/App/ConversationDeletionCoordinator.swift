import Foundation
import SwiftData

@MainActor
final class ConversationDeletionCoordinator {
    private let context: ModelContext
    private let scheduler: NotionSyncScheduling
    private let attachmentStore: AttachmentStore?

    init(
        context: ModelContext,
        scheduler: NotionSyncScheduling,
        attachmentStore: AttachmentStore? = nil
    ) {
        self.context = context
        self.scheduler = scheduler
        self.attachmentStore = attachmentStore
    }

    func delete(conversation: Conversation) async {
        let conversationID = conversation.id
        scheduler.cancel(conversationID: conversationID)
        if let attachmentStore {
            try? await attachmentStore.deleteConversationAttachments(conversationID: conversationID)
        }
        context.delete(conversation)
        try? context.save()
    }
}
