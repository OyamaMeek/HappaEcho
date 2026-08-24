import Foundation
import SwiftData

struct NotionSyncConfiguration: Sendable {
    var enabled: Bool
    var databaseID: String?
}

struct NotionSyncMessage: Sendable {
    var id: UUID
    var conversationID: UUID
    var role: MessageRole
    var content: String
    var createdAt: Date
    var sequence: Int
    var nextBatchIndex: Int
    var syncState: SyncState
    var hasAttachments: Bool
}

struct NotionSyncConversation: Sendable {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var modelID: String?
    var pageID: String?
    var pageDatabaseID: String?
}

@MainActor
protocol NotionSyncModelStore: AnyObject {
    func configuration() throws -> NotionSyncConfiguration
    func message(id: UUID) throws -> NotionSyncMessage?
    func conversation(id: UUID) throws -> NotionSyncConversation?
    func pendingMessageIDs() throws -> [UUID]
    func markSyncing(messageID: UUID) throws
    func bindPage(conversationID: UUID, databaseID: String, pageID: String) throws
    func confirmBatch(messageID: UUID, index: Int, blockIDs: [String]) throws
    func markSynced(messageID: UUID) throws
    func markFailed(messageID: UUID, error: String) throws
}

@MainActor
final class SwiftDataNotionSyncModelStore: NotionSyncModelStore {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func configuration() throws -> NotionSyncConfiguration {
        let settings = try modelContext.fetch(FetchDescriptor<AppSettings>()).first
        return .init(enabled: settings?.notionEnabled ?? false, databaseID: settings?.notionDatabaseID)
    }

    func message(id: UUID) throws -> NotionSyncMessage? {
        guard let message = try modelContext.fetch(FetchDescriptor<Message>()).first(where: { $0.id == id }),
              let conversation = message.conversation else { return nil }
        return .init(id: message.id, conversationID: conversation.id, role: message.role, content: message.content, createdAt: message.createdAt, sequence: message.sequence, nextBatchIndex: message.nextNotionBatchIndex, syncState: message.syncState, hasAttachments: !message.attachments.isEmpty)
    }

    func conversation(id: UUID) throws -> NotionSyncConversation? {
        guard let conversation = try modelContext.fetch(FetchDescriptor<Conversation>()).first(where: { $0.id == id }) else { return nil }
        let binding = conversation.activePageBinding
        return .init(id: conversation.id, title: conversation.title, createdAt: conversation.createdAt, updatedAt: conversation.updatedAt, modelID: conversation.modelID, pageID: binding?.pageID, pageDatabaseID: binding?.databaseID)
    }

    func pendingMessageIDs() throws -> [UUID] {
        try modelContext.fetch(FetchDescriptor<Message>())
            .filter { $0.syncState == .pending || $0.syncState == .failed }
            .sorted { $0.sequence < $1.sequence }
            .map(\.id)
    }

    func markSyncing(messageID: UUID) throws {
        guard let message = try modelContext.fetch(FetchDescriptor<Message>()).first(where: { $0.id == messageID }) else { return }
        message.syncState = .syncing
        message.syncError = nil
        try modelContext.save()
    }

    func bindPage(conversationID: UUID, databaseID: String, pageID: String) throws {
        guard let conversation = try modelContext.fetch(FetchDescriptor<Conversation>()).first(where: { $0.id == conversationID }) else { return }
        let binding = conversation.bindNotionPage(databaseID: databaseID, pageID: pageID)
        modelContext.insert(binding)
        try modelContext.save()
    }

    func confirmBatch(messageID: UUID, index: Int, blockIDs: [String]) throws {
        guard let message = try modelContext.fetch(FetchDescriptor<Message>()).first(where: { $0.id == messageID }) else { return }
        guard message.nextNotionBatchIndex <= index else { return }
        message.confirmBatch(index: index, blockIDs: blockIDs)
        try modelContext.save()
    }

    func markSynced(messageID: UUID) throws {
        guard let message = try modelContext.fetch(FetchDescriptor<Message>()).first(where: { $0.id == messageID }) else { return }
        message.syncState = .synced
        message.syncError = nil
        message.lastSyncedAt = .now
        try modelContext.save()
    }

    func markFailed(messageID: UUID, error: String) throws {
        guard let message = try modelContext.fetch(FetchDescriptor<Message>()).first(where: { $0.id == messageID }) else { return }
        message.syncState = .failed
        message.syncError = error
        try modelContext.save()
    }
}

protocol NotionSyncSleeping: Sendable {
    func sleep(for delay: TimeInterval) async throws
}

struct ImmediateNotionSyncSleeper: NotionSyncSleeping {
    func sleep(for delay: TimeInterval) async throws {}
}

actor NotionSyncCoordinator {
    private let service: any NotionService
    private let store: any NotionSyncModelStore
    private let sleeper: any NotionSyncSleeping
    private let formatter = NotionBlockFormatter()
    private var queues: [UUID: [UUID]] = [:]
    private var workers: [UUID: Task<Void, Never>] = [:]

    init(service: any NotionService, store: any NotionSyncModelStore, sleeper: any NotionSyncSleeping = ImmediateNotionSyncSleeper()) {
        self.service = service
        self.store = store
        self.sleeper = sleeper
    }

    func enqueue(messageID: UUID) async {
        guard let message = try? await store.message(id: messageID) else { return }
        var queue = queues[message.conversationID, default: []]
        if !queue.contains(messageID) { queue.append(messageID) }
        queues[message.conversationID] = queue
        startWorkerIfNeeded(for: message.conversationID)
    }

    func enqueueMetadata(conversationID: UUID) async {
        startWorkerIfNeeded(for: conversationID)
    }

    func resumePending() async {
        guard let ids = try? await store.pendingMessageIDs() else { return }
        for id in ids { await enqueue(messageID: id) }
    }

    func cancel(conversationID: UUID) {
        workers[conversationID]?.cancel()
        workers[conversationID] = nil
        queues[conversationID] = []
    }

    private func startWorkerIfNeeded(for conversationID: UUID) {
        guard workers[conversationID] == nil else { return }
        workers[conversationID] = Task { [weak self] in
            await self?.drain(conversationID: conversationID)
        }
    }

    private func drain(conversationID: UUID) async {
        defer { workers[conversationID] = nil }
        while !Task.isCancelled {
            guard var queue = queues[conversationID], !queue.isEmpty else { return }
            let messageID = queue.removeFirst()
            queues[conversationID] = queue
            await sync(messageID: messageID)
        }
    }

    private func sync(messageID: UUID) async {
        do {
            let config = try await store.configuration()
            guard config.enabled, let databaseID = config.databaseID, !databaseID.isEmpty else { return }
            guard let message = try await store.message(id: messageID),
                  let conversation = try await store.conversation(id: message.conversationID) else { return }
            guard message.syncState != .synced else { return }
            try Task.checkCancellation()
            try await store.markSyncing(messageID: messageID)

            let pageID: String
            if conversation.pageDatabaseID == databaseID, let existing = conversation.pageID {
                pageID = existing
            } else {
                let properties: [String: NotionProperty] = [
                    "Title": .title(conversation.title), "Created": .date(conversation.createdAt),
                    "Updated": .date(conversation.updatedAt), "Model": .richText(conversation.modelID ?? ""),
                    "MessageCount": .number(0), "Status": .select("syncing")
                ]
                let page = try await attempt { try await self.service.createPage(.init(databaseID: databaseID, properties: properties)) }
                try Task.checkCancellation()
                try await store.bindPage(conversationID: message.conversationID, databaseID: databaseID, pageID: page.id)
                pageID = page.id
            }

            let model = Message(id: message.id, role: message.role, content: message.content, createdAt: message.createdAt, sequence: message.sequence, nextNotionBatchIndex: message.nextBatchIndex)
            let batches = try formatter.batches(for: model)
            for batch in batches where batch.index >= message.nextBatchIndex {
                try Task.checkCancellation()
                let ids = try await attempt { try await self.service.appendBlocks(pageID: pageID, blocks: batch.blocks) }
                try Task.checkCancellation()
                try await store.confirmBatch(messageID: messageID, index: batch.index, blockIDs: ids)
            }
            try await store.markSynced(messageID: messageID)
        } catch is CancellationError {
        } catch {
            try? await store.markFailed(messageID: messageID, error: error.localizedDescription)
        }
    }

    private func attempt<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        var delay: TimeInterval = 1
        for attempt in 0..<3 {
            do { return try await operation() }
            catch let error as NotionError where isTransient(error) && attempt < 2 {
                if case let .rateLimited(retryAfter) = error { delay = max(delay, retryAfter ?? 0) }
                try await sleeper.sleep(for: delay)
                delay *= 2
            }
        }
        throw NotionError.network(code: nil)
    }

    private func isTransient(_ error: NotionError) -> Bool {
        switch error {
        case .rateLimited, .server, .network: true
        default: false
        }
    }
}
