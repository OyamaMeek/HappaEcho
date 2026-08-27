import Foundation
import SwiftData

protocol TitleSyncScheduling: Sendable {
    func enqueueMetadata(conversationID: UUID)
}

extension TitleSyncScheduling {
    func enqueueMetadata(conversationID: UUID) {}
}

@MainActor
protocol ConversationTitleGenerating: AnyObject {
    func generateIfEligible(for conversation: Conversation) async
    func setManualTitle(_ title: String, for conversation: Conversation) async throws
}

@MainActor
final class TitleGenerationCoordinator: ConversationTitleGenerating {
    private let service: ChatCompletionService
    private let modelContext: ModelContext
    private let syncScheduler: TitleSyncScheduling
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var tokens: [UUID: UUID] = [:]

    init(service: ChatCompletionService, modelContext: ModelContext, syncScheduler: TitleSyncScheduling) {
        self.service = service
        self.modelContext = modelContext
        self.syncScheduler = syncScheduler
    }

    func generateIfEligible(for conversation: Conversation) async {
        guard !conversation.isTitleManuallyEdited else { return }
        let firstUser = conversation.sortedMessages.first(where: { $0.role == .user })
        guard let firstUser else { return }
        let firstAssistant = conversation.sortedMessages.first(where: { $0.role == .assistant && $0.generationState == .completed })
        guard let firstAssistant else {
            applyFallback(firstUser.content, to: conversation)
            return
        }
        guard !conversation.titleGenerationAttempted, tasks[conversation.id] == nil else {
            return
        }

        // Establish the deterministic title before starting the request. This
        // remains visible if the provider fails and is protected by the same
        // manual-edit guard as generated output.
        applyFallback(firstUser.content, to: conversation)
        conversation.titleGenerationAttempted = true
        try? modelContext.save()
        let token = UUID()
        tokens[conversation.id] = token
        let service = service
        let request = TitleRequest(model: conversation.modelID ?? "", messages: [
            ChatInputMessage(role: .system, content: [.text("Generate a short conversation title.")]),
            ChatInputMessage(role: .user, content: [.text(firstUser.content)]),
            ChatInputMessage(role: .assistant, content: [.text(firstAssistant.content)])
        ])
        tasks[conversation.id] = Task { [weak self, weak conversation] in
            guard let self, let conversation else { return }
            do {
                let output = try await service.generateTitle(request: request)
                guard !Task.isCancelled else { return }
                self.applyGenerated(output, to: conversation, token: token)
            } catch {
                // The fallback was applied before this request started.
            }
            self.clearTask(for: conversation.id, token: token)
        }
        await tasks[conversation.id]?.value
    }

    func setManualTitle(_ title: String, for conversation: Conversation) async throws {
        tasks[conversation.id]?.cancel()
        tokens[conversation.id] = UUID()
        conversation.isTitleManuallyEdited = true
        let normalized = normalize(title)
        if !normalized.isEmpty { conversation.title = normalized }
        try modelContext.save()
        syncScheduler.enqueueMetadata(conversationID: conversation.id)
    }

    private func applyFallback(_ text: String, to conversation: Conversation) {
        guard !conversation.isTitleManuallyEdited else { return }
        let value = normalize(text)
        guard !value.isEmpty, conversation.title != value else { return }
        conversation.title = value
        try? modelContext.save()
        syncScheduler.enqueueMetadata(conversationID: conversation.id)
    }

    private func applyGenerated(_ output: String, to conversation: Conversation, token: UUID) {
        guard tokens[conversation.id] == token, !conversation.isTitleManuallyEdited else { return }
        let value = normalize(output)
        guard !value.isEmpty else { return }
        conversation.title = value
        try? modelContext.save()
        syncScheduler.enqueueMetadata(conversationID: conversation.id)
    }

    private func clearTask(for id: UUID, token: UUID) {
        guard tokens[id] == token else { return }
        tasks[id] = nil
    }

    private func normalize(_ value: String) -> String {
        var result = value.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if result.count >= 2, result.first == "\"", result.last == "\"" { result.removeFirst(); result.removeLast() }
        return String(result.prefix(30)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
