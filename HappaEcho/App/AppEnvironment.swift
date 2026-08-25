import Foundation
import SwiftData

@MainActor
final class AppEnvironment {
    let container: ModelContainer
    let settingsRepository: SettingsRepository
    let syncScheduler: NotionSyncScheduling
    let attachmentStore: AttachmentStore

    init(
        container: ModelContainer = try! HappaEchoSchema.makeContainer(inMemory: false),
        settingsRepository: SettingsRepository = .init(),
        syncScheduler: NotionSyncScheduling = NoopNotionScheduler(),
        attachmentStore: AttachmentStore = AttachmentStore()
    ) {
        self.container = container
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
        return ChatSessionController(
            service: service,
            modelContext: context,
            attachmentStore: attachmentStore,
            syncScheduler: syncScheduler,
            settings: .init(modelID: settings.modelID, supportsVision: settings.supportsVision, systemPrompt: settings.systemPrompt)
        )
    }

    func resumePending() { syncScheduler.resumePending() }
}

final class NoopNotionScheduler: NotionSyncScheduling, @unchecked Sendable {
    func enqueue(messageID: UUID) {}
    func cancel(conversationID: UUID) {}
}
