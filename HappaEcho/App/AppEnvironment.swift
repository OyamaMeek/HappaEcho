import Foundation
import SwiftData

@MainActor
final class AppEnvironment {
    let container: ModelContainer
    let settingsRepository: SettingsRepository
    let syncScheduler: NotionSyncScheduling
    let attachmentStore: AttachmentStore

    init(
        container: ModelContainer? = nil,
        settingsRepository: SettingsRepository = .init(),
        syncScheduler: NotionSyncScheduling = NoopNotionScheduler(),
        attachmentStore: AttachmentStore = AttachmentStore()
    ) throws {
        self.container = try container ?? HappaEchoSchema.makeContainer(inMemory: false)
        self.settingsRepository = settingsRepository
        self.syncScheduler = syncScheduler
        self.attachmentStore = attachmentStore
    }

    func settings(context: ModelContext) -> AppSettings {
        let descriptor = FetchDescriptor<AppSettings>()
        if let settings = try? context.fetch(descriptor).first { return settings }
        let settings = AppSettings()
        context.insert(settings)
        try? context.save()
        return settings
    }

    func makeChatSession(context: ModelContext, settings: AppSettings) -> ChatSessionController {
        let endpoint = URL(string: settings.endpoint) ?? URL(string: "https://api.openai.com/v1/chat/completions")!
        let apiKey = (try? settingsRepository.loadChatAPIKey()) ?? ""
        let service = OpenAICompatibleClient(configuration: .init(endpoint: endpoint, apiKey: apiKey))
        let titleGenerator = TitleGenerationCoordinator(
            service: service,
            modelContext: context,
            syncScheduler: NotionTitleSyncScheduler(scheduler: syncScheduler)
        )
        return ChatSessionController(
            service: service,
            modelContext: context,
            attachmentStore: attachmentStore,
            syncScheduler: syncScheduler,
            settings: .init(modelID: settings.modelID, supportsVision: settings.supportsVision, systemPrompt: settings.systemPrompt),
            titleGenerator: titleGenerator
        )
    }

    func resumePending() { syncScheduler.resumePending() }
}

final class NoopNotionScheduler: NotionSyncScheduling, @unchecked Sendable {
    func enqueue(messageID: UUID) {}
    func enqueueMetadata(conversationID: UUID) {}
    func resumePending() {}
    func cancel(conversationID: UUID) {}
}

private final class NotionTitleSyncScheduler: TitleSyncScheduling, @unchecked Sendable {
    private let scheduler: any NotionSyncScheduling

    init(scheduler: any NotionSyncScheduling) {
        self.scheduler = scheduler
    }

    func enqueueMetadata(conversationID: UUID) {
        scheduler.enqueueMetadata(conversationID: conversationID)
    }
}
