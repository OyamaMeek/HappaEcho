import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class ChatSessionController {
    private let service: ChatCompletionService
    private let modelContext: ModelContext
    private let attachmentStore: AttachmentStore
    private let syncScheduler: NotionSyncScheduling
    private let settings: ChatSessionSettings
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var states: [UUID: ChatSessionState] = [:]
    private var drafts: [UUID: ChatDraft] = [:]

    init(
        service: ChatCompletionService,
        modelContext: ModelContext,
        attachmentStore: AttachmentStore,
        syncScheduler: NotionSyncScheduling,
        settings: ChatSessionSettings
    ) {
        self.service = service
        self.modelContext = modelContext
        self.attachmentStore = attachmentStore
        self.syncScheduler = syncScheduler
        self.settings = settings
    }

    func state(for conversationID: UUID) -> ChatSessionState {
        states[conversationID] ?? .idle
    }

    func restoredDraft(for conversationID: UUID) -> ChatDraft? {
        drafts[conversationID]
    }

    func send(text: String, attachments: [MessageAttachment], conversation: Conversation) async {
        guard tasks[conversation.id] == nil else { return }
        guard hasUniqueSequences(in: conversation) else {
            states[conversation.id] = .failed(message: "Message sequence invariant violated")
            return
        }
        guard attachments.isEmpty || settings.supportsVision else {
            states[conversation.id] = .blocked(.unsupportedVision)
            return
        }

        let message = Message(role: .user, content: text, sequence: nextSequence(in: conversation))
        for attachment in attachments.sorted(by: { $0.userOrder < $1.userOrder }) {
            attachment.message = message
            message.attachments.append(attachment)
        }
        guard persist(message, in: conversation) else {
            drafts[conversation.id] = ChatDraft(text: text, attachments: attachments)
            states[conversation.id] = .failed(message: "Unable to save message")
            return
        }
        do {
            let request = try await makeRequest(from: conversation)
            beginGeneration(in: conversation, request: request, draft: ChatDraft(messageID: message.id, text: text, attachments: attachments))
        } catch {
            drafts[conversation.id] = ChatDraft(text: text, attachments: attachments)
            states[conversation.id] = .failed(message: error.localizedDescription)
        }
        await Task.yield()
    }

    func continueGeneration(after message: Message, in conversation: Conversation) async {
        guard message.generationState == .failedPartial, tasks[conversation.id] == nil else { return }
        guard hasUniqueSequences(in: conversation) else {
            states[conversation.id] = .failed(message: "Message sequence invariant violated")
            return
        }
        do {
            let messages = try await buildInputMessages(from: conversation, through: message.sequence)
            beginGeneration(in: conversation, request: ChatRequest(model: conversation.modelID ?? settings.modelID, messages: withSystemPrompt(messages)), draft: nil)
        } catch {
            states[conversation.id] = .failed(message: error.localizedDescription)
        }
        await Task.yield()
    }

    func retryRestoredDraft(in conversation: Conversation) async {
        guard let draft = drafts[conversation.id], tasks[conversation.id] == nil else { return }
        guard let messageID = draft.messageID,
              conversation.messages.contains(where: { $0.id == messageID }) else {
            await send(text: draft.text, attachments: draft.attachments, conversation: conversation)
            return
        }
        do {
            let request = try await makeRequest(from: conversation)
            drafts[conversation.id] = nil
            beginGeneration(in: conversation, request: request, draft: draft)
        } catch {
            states[conversation.id] = .failed(message: error.localizedDescription)
        }
        await Task.yield()
    }

    func stop(conversationID: UUID) {
        tasks[conversationID]?.cancel()
    }

    private func beginGeneration(in conversation: Conversation, request: ChatRequest, draft: ChatDraft?) {
        let id = conversation.id
        conversation.isGenerating = true
        states[id] = .generating(text: "")
        let service = service
        tasks[id] = Task { [weak self, weak conversation] in
            guard let self, let conversation else { return }
            var accumulated = ""
            var wasCancelled = false
            do {
                try await withTaskCancellationHandler(operation: {
                    for try await delta in service.stream(request: request) {
                        try Task.checkCancellation()
                        accumulated += delta
                        self.states[id] = .generating(text: accumulated)
                    }
                }, onCancel: {
                    wasCancelled = true
                })
                try Task.checkCancellation()
                self.finish(text: accumulated, state: .completed, conversation: conversation, id: id)
            } catch is CancellationError {
                self.finishCancellation(text: accumulated, conversation: conversation, id: id)
            } catch {
                if Task.isCancelled || wasCancelled {
                    self.finishCancellation(text: accumulated, conversation: conversation, id: id)
                } else {
                    self.finishFailure(error: error, text: accumulated, draft: draft, conversation: conversation, id: id)
                }
            }
        }
    }

    private func finish(text: String, state: GenerationState, conversation: Conversation, id: UUID) {
        if !text.isEmpty {
            let message = Message(role: .assistant, content: text, sequence: nextSequence(in: conversation), generationState: state)
            persist(message, in: conversation)
        }
        conclude(conversation: conversation, id: id, state: .idle)
    }

    private func finishCancellation(text: String, conversation: Conversation, id: UUID) {
        if !text.isEmpty {
            let message = Message(role: .assistant, content: text, sequence: nextSequence(in: conversation), generationState: .stopped)
            persist(message, in: conversation)
            conclude(conversation: conversation, id: id, state: .stopped(text: text))
        } else {
            conclude(conversation: conversation, id: id, state: .idle)
        }
    }

    private func finishFailure(error: Error, text: String, draft: ChatDraft?, conversation: Conversation, id: UUID) {
        if !text.isEmpty {
            let message = Message(role: .assistant, content: text, sequence: nextSequence(in: conversation), generationState: .failedPartial)
            persist(message, in: conversation)
        } else if let draft, isContextLimit(error) {
            drafts[id] = draft
        }
        conclude(conversation: conversation, id: id, state: .failed(message: error.localizedDescription))
    }

    private func conclude(conversation: Conversation, id: UUID, state: ChatSessionState) {
        conversation.isGenerating = false
        states[id] = state
        tasks[id] = nil
        try? modelContext.save()
    }

    private func persist(_ message: Message, in conversation: Conversation) -> Bool {
        message.conversation = conversation
        conversation.messages.append(message)
        conversation.updatedAt = .now
        modelContext.insert(message)
        do {
            try modelContext.save()
            syncScheduler.enqueue(messageID: message.id)
            return true
        } catch {
            modelContext.delete(message)
            conversation.messages.removeAll { $0.id == message.id }
            return false
        }
    }

    private func nextSequence(in conversation: Conversation) -> Int {
        (conversation.messages.map(\.sequence).max() ?? -1) + 1
    }

    private func hasUniqueSequences(in conversation: Conversation) -> Bool {
        let sequences = conversation.messages.map(\.sequence)
        return sequences.count == Set(sequences).count
    }

    private func makeRequest(from conversation: Conversation) async throws -> ChatRequest {
        ChatRequest(model: conversation.modelID ?? settings.modelID, messages: withSystemPrompt(try await buildInputMessages(from: conversation)))
    }

    private func buildInputMessages(from conversation: Conversation, through sequence: Int? = nil) async throws -> [ChatInputMessage] {
        var messages: [ChatInputMessage] = []
        for message in conversation.sortedMessages where sequence.map({ message.sequence <= $0 }) ?? true {
            var content: [ChatContentPart] = [.text(message.content)]
            if message.role == .user {
                for attachment in message.attachments.sorted(by: { $0.userOrder < $1.userOrder }) {
                    let data = try await attachmentStore.data(for: attachment)
                    content.append(.image(.init(mimeType: attachment.mimeType, base64: data.base64EncodedString())))
                }
            }
            messages.append(ChatInputMessage(role: message.role == .user ? .user : .assistant, content: content))
        }
        return messages
    }

    private func withSystemPrompt(_ messages: [ChatInputMessage]) -> [ChatInputMessage] {
        guard let prompt = settings.systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty else { return messages }
        return [ChatInputMessage(role: .system, content: [.text(prompt)])] + messages
    }

    private func makeInput(_ message: Message) -> ChatInputMessage {
        let role: ChatRole = message.role == .user ? .user : .assistant
        return ChatInputMessage(role: role, content: [.text(message.content)])
    }

    private func isContextLimit(_ error: Error) -> Bool {
        guard case let ChatServiceError.invalidRequest(message) = error else { return false }
        return message?.localizedCaseInsensitiveContains("context") == true
    }
}
