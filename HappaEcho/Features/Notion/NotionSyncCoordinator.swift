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

struct NotionSyncAttachment: Sendable {
    var id: UUID
    var filename: String
    var contentType: String
    var fileURL: URL
    var syncState: SyncState
    var uploadID: String?
    var uploadSentAt: Date?
    var remoteURL: String?
    var imageBlockID: String?
}
@MainActor
protocol NotionSyncModelStore: AnyObject {
    func configuration() throws -> NotionSyncConfiguration
    func message(id: UUID) throws -> NotionSyncMessage?
    func attachments(messageID: UUID) throws -> [NotionSyncAttachment]
    func conversation(id: UUID) throws -> NotionSyncConversation?
    func pageProperties(conversationID: UUID) throws -> [String: NotionProperty]
    func pendingMessageIDs() throws -> [UUID]
    func messageIDs(conversationID: UUID) throws -> [UUID]
    func resetPageCheckpoints(conversationID: UUID) throws
    func markSyncing(messageID: UUID) throws
    func bindPage(conversationID: UUID, databaseID: String, pageID: String) throws
    func confirmBatch(messageID: UUID, index: Int, blockIDs: [String]) throws
    func saveAttachmentUploadID(attachmentID: UUID, uploadID: String) throws
    func markAttachmentSent(attachmentID: UUID) throws
    func saveAttachmentRemoteURL(attachmentID: UUID, remoteURL: String?) throws
    func completeAttachment(attachmentID: UUID, imageBlockID: String) throws
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

    func attachments(messageID: UUID) throws -> [NotionSyncAttachment] {
        guard let message = try modelContext.fetch(FetchDescriptor<Message>()).first(where: { $0.id == messageID }) else { return [] }
        let rootURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "HappaEcho/Attachments", directoryHint: .isDirectory)
        return message.attachments.sorted { $0.userOrder < $1.userOrder }.map {
            .init(id: $0.id, filename: $0.originalFileName, contentType: $0.mimeType, fileURL: rootURL.appending(path: $0.relativePath), syncState: $0.syncState, uploadID: $0.notionUploadID, uploadSentAt: $0.notionUploadSentAt, remoteURL: $0.notionRemoteURL, imageBlockID: $0.notionImageBlockID)
        }
    }

    func conversation(id: UUID) throws -> NotionSyncConversation? {
        guard let conversation = try modelContext.fetch(FetchDescriptor<Conversation>()).first(where: { $0.id == id }) else { return nil }
        let binding = conversation.activePageBinding
        return .init(id: conversation.id, title: conversation.title, createdAt: conversation.createdAt, updatedAt: conversation.updatedAt, modelID: conversation.modelID, pageID: binding?.pageID, pageDatabaseID: binding?.databaseID)
    }

    func pageProperties(conversationID: UUID) throws -> [String: NotionProperty] {
        guard let conversation = try modelContext.fetch(FetchDescriptor<Conversation>()).first(where: { $0.id == conversationID }) else { return [:] }
        return NotionBlockFormatter().pageProperties(for: conversation)
    }

    func pendingMessageIDs() throws -> [UUID] {
        try modelContext.fetch(FetchDescriptor<Message>())
            .filter { $0.syncState == .pending || $0.syncState == .failed }
            .sorted { $0.sequence < $1.sequence }
            .map(\.id)
    }

    func messageIDs(conversationID: UUID) throws -> [UUID] {
        try modelContext.fetch(FetchDescriptor<Message>())
            .filter { $0.conversation?.id == conversationID }
            .sorted { $0.sequence < $1.sequence }
            .map(\.id)
    }

    func resetPageCheckpoints(conversationID: UUID) throws {
        let messages = try modelContext.fetch(FetchDescriptor<Message>()).filter { $0.conversation?.id == conversationID }
        for message in messages {
            message.nextNotionBatchIndex = 0
            message.confirmedBatchIDs = []
            message.confirmedBlockIDs = []
            message.lastConfirmedAt = nil
            message.lastSyncedAt = nil
            message.syncState = .pending
            for attachment in message.attachments {
                attachment.syncState = .pending
                attachment.notionUploadID = nil
                attachment.notionUploadSentAt = nil
                attachment.notionRemoteURL = nil
                attachment.notionImageBlockID = nil
                attachment.syncError = nil
            }
        }
        try modelContext.save()
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

    func saveAttachmentUploadID(attachmentID: UUID, uploadID: String) throws {
        guard let attachment = try modelContext.fetch(FetchDescriptor<MessageAttachment>()).first(where: { $0.id == attachmentID }) else { return }
        attachment.notionUploadID = uploadID
        attachment.syncState = .syncing
        attachment.syncError = nil
        try modelContext.save()
    }

    func markAttachmentSent(attachmentID: UUID) throws {
        guard let attachment = try modelContext.fetch(FetchDescriptor<MessageAttachment>()).first(where: { $0.id == attachmentID }) else { return }
        attachment.notionUploadSentAt = .now
        try modelContext.save()
    }

    func saveAttachmentRemoteURL(attachmentID: UUID, remoteURL: String?) throws {
        guard let attachment = try modelContext.fetch(FetchDescriptor<MessageAttachment>()).first(where: { $0.id == attachmentID }) else { return }
        attachment.notionRemoteURL = remoteURL
        try modelContext.save()
    }

    func completeAttachment(attachmentID: UUID, imageBlockID: String) throws {
        guard let attachment = try modelContext.fetch(FetchDescriptor<MessageAttachment>()).first(where: { $0.id == attachmentID }) else { return }
        attachment.notionImageBlockID = imageBlockID
        attachment.syncState = .synced
        attachment.syncError = nil
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
    private var metadataQueues: Set<UUID> = []
    private var replayingConversations: Set<UUID> = []
    private var workers: [UUID: Task<Void, Never>] = [:]
    private var workerTokens: [UUID: UUID] = [:]

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
        metadataQueues.insert(conversationID)
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
        metadataQueues.remove(conversationID)
    }

    private func startWorkerIfNeeded(for conversationID: UUID) {
        guard workers[conversationID] == nil else { return }
        let token = UUID()
        workerTokens[conversationID] = token
        workers[conversationID] = Task { [weak self] in
            await self?.drain(conversationID: conversationID, token: token)
        }
    }

    private func drain(conversationID: UUID, token: UUID) async {
        defer {
            if workerTokens[conversationID] == token {
                workers[conversationID] = nil
                workerTokens[conversationID] = nil
            }
        }
        while !Task.isCancelled {
            if metadataQueues.remove(conversationID) != nil {
                await syncMetadata(conversationID: conversationID)
                continue
            }
            guard var queue = queues[conversationID], !queue.isEmpty else { return }
            let messageID = queue.removeFirst()
            queues[conversationID] = queue
            await sync(messageID: messageID)
        }
    }

    private func syncMetadata(conversationID: UUID) async {
        do {
            let config = try await store.configuration()
            guard config.enabled, let databaseID = config.databaseID, !databaseID.isEmpty,
                  let conversation = try await store.conversation(id: conversationID),
                  conversation.pageDatabaseID == databaseID,
                  let pageID = conversation.pageID else { return }
            let properties = try await store.pageProperties(conversationID: conversationID)
            try await attempt { try await self.service.updatePageProperties(pageID: pageID, properties: properties) }
        } catch {
            // Metadata backup is retried on the next coalesced schedule event.
        }
    }

    private func sync(messageID: UUID) async {
        do {
            let config = try await store.configuration()
            guard config.enabled, let databaseID = config.databaseID, !databaseID.isEmpty else { return }
            guard var message = try await store.message(id: messageID),
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
                if !replayingConversations.contains(message.conversationID) {
                    replayingConversations.insert(message.conversationID)
                    try await store.resetPageCheckpoints(conversationID: message.conversationID)
                    let historicalIDs = try await store.messageIDs(conversationID: message.conversationID)
                    var queue = queues[message.conversationID, default: []]
                    for historicalID in historicalIDs.reversed() where !queue.contains(historicalID) {
                        queue.insert(historicalID, at: 0)
                    }
                    queues[message.conversationID] = queue
                    return
                }
                pageID = page.id
            }

            let model = Message(id: message.id, role: message.role, content: message.content, createdAt: message.createdAt, sequence: message.sequence, nextNotionBatchIndex: message.nextBatchIndex)
            let batches = try formatter.batches(for: model)
            for batch in batches where batch.index >= message.nextBatchIndex {
                try Task.checkCancellation()
                let blockIDs = try await appendBatch(pageID: pageID, batch: batch)
                try Task.checkCancellation()
                try await store.confirmBatch(messageID: messageID, index: batch.index, blockIDs: blockIDs)
            }
            for attachment in try await store.attachments(messageID: messageID) where attachment.imageBlockID == nil {
                try Task.checkCancellation()
                let uploadID: String
                if let existing = attachment.uploadID {
                    uploadID = existing
                } else {
                    let upload = try await attempt { try await self.service.createFileUpload(.init(filename: attachment.filename, contentType: attachment.contentType)) }
                    try await store.saveAttachmentUploadID(attachmentID: attachment.id, uploadID: upload.id)
                    uploadID = upload.id
                }
                if attachment.uploadSentAt == nil {
                    // A lost send response is ambiguous: retransmitting may upload the
                    // same bytes again. Persist the send intent first, then let the
                    // complete endpoint determine whether Notion accepted the upload.
                    try await store.markAttachmentSent(attachmentID: attachment.id)
                    try await service.sendFile(uploadID: uploadID, fileURL: attachment.fileURL, contentType: attachment.contentType)
                }
                if attachment.remoteURL == nil {
                    let completed = try await attempt { try await self.service.completeFileUpload(uploadID: uploadID) }
                    try await store.saveAttachmentRemoteURL(attachmentID: attachment.id, remoteURL: completed.fileURL?.absoluteString)
                }
                let imageBlockIDs = try await appendImageBlock(pageID: pageID, uploadID: uploadID, attachmentID: attachment.id)
                guard let imageBlockID = imageBlockIDs.first else { throw NotionError.invalidResponse }
                try await store.completeAttachment(attachmentID: attachment.id, imageBlockID: imageBlockID)
            }
            try await store.markSynced(messageID: messageID)
            metadataQueues.insert(message.conversationID)
        } catch is CancellationError {
        } catch {
            try? await store.markFailed(messageID: messageID, error: error.localizedDescription)
        }
    }

    private func appendImageBlock(pageID: String, uploadID: String, attachmentID: UUID) async throws -> [String] {
        let marker = "happaecho-attachment:\(attachmentID.uuidString.lowercased())"
        for index in 0..<3 {
            if let blockIDs = try await reconciledBlockIDs(marker: marker, pageID: pageID) {
                return blockIDs
            }
            do {
                return try await service.appendBlocks(pageID: pageID, blocks: [.init(kind: .image(fileUploadID: uploadID, marker: marker), richText: [], markerMessageID: nil)])
            } catch {
                guard let notionError = error as? NotionError,
                      isTransient(notionError),
                      index < 2 else { throw error }
                let delay: TimeInterval
                if case let .rateLimited(retryAfter) = notionError {
                    delay = retryAfter ?? pow(2, Double(index))
                } else {
                    delay = pow(2, Double(index))
                }
                try await sleeper.sleep(for: delay)
            }
        }
        throw NotionError.network(code: nil)
    }

    private func appendBatch(pageID: String, batch: NotionBlockBatch) async throws -> [String] {
        var delay: TimeInterval = 1
        var lastError: Error?
        for index in 0..<3 {
            if let blockIDs = try await reconciledBlockIDs(marker: batch.marker, pageID: pageID) {
                return blockIDs
            }
            do {
                return try await service.appendBlocks(pageID: pageID, blocks: batch.blocks)
            } catch {
                lastError = error
                guard let notionError = error as? NotionError,
                      isTransient(notionError),
                      index < 2 else { throw error }
                if case let .rateLimited(retryAfter) = notionError {
                    delay = max(delay, retryAfter ?? 0)
                }
                try await sleeper.sleep(for: delay)
                delay *= 2
            }
        }
        throw lastError ?? NotionError.network(code: nil)
    }

    private func reconciledBlockIDs(marker: String, pageID: String) async throws -> [String]? {
        var cursor: String?
        repeat {
            let page = try await attempt { try await self.service.listBlocks(pageID: pageID, cursor: cursor) }
            if let markerBlock = page.blocks.first(where: { $0.plainText == marker }) {
                return [markerBlock.remoteID].compactMap { $0 }
            }
            cursor = page.hasMore ? page.nextCursor : nil
        } while cursor != nil
        return nil
    }

    private func attempt<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        var delay: TimeInterval = 1
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                return try await operation()
            } catch {
                lastError = error
                guard let notionError = error as? NotionError,
                      isTransient(notionError),
                      attempt < 2 else { throw error }
                if case let .rateLimited(retryAfter) = notionError {
                    delay = max(delay, retryAfter ?? 0)
                }
                try await sleeper.sleep(for: delay)
                delay *= 2
            }
        }
        throw lastError ?? NotionError.network(code: nil)
    }

    private func isTransient(_ error: NotionError) -> Bool {
        switch error {
        case .rateLimited, .server, .network: true
        default: false
        }
    }
}
