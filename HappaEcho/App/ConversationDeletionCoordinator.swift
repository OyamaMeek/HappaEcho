import Foundation
import SwiftData
@MainActor final class ConversationDeletionCoordinator { let context:ModelContext; let scheduler:NotionSyncScheduling; let attachmentStore:AttachmentStore?; init(context:ModelContext,scheduler:NotionSyncScheduling,attachmentStore:AttachmentStore?=nil){self.context=context;self.scheduler=scheduler;self.attachmentStore=attachmentStore}; func delete(conversation:Conversation) async { scheduler.cancel(conversationID:conversation.id); context.delete(conversation); try? context.save(); _ = attachmentStore } }
