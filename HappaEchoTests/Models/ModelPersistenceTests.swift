import XCTest
import SwiftData
@testable import HappaEcho

/// Persistence contracts for the SwiftData domain model consumed by Tasks 6–9.
@MainActor
final class ModelPersistenceTests: XCTestCase {
    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        try HappaEchoSchema.makeContainer(inMemory: true)
    }

    // MARK: - Message defaults

    func testNewMessageStartsPending() {
        let message = Message(role: .user, content: "你好", sequence: 0)
        XCTAssertEqual(message.syncState, .pending)
    }

    func testNewMessageHasEmptyNotionCheckpoints() {
        let message = Message(role: .assistant, content: "回复", sequence: 1)
        XCTAssertEqual(message.nextNotionBatchIndex, 0)
        XCTAssertTrue(message.confirmedBatchIDs.isEmpty)
        XCTAssertTrue(message.confirmedBlockIDs.isEmpty)
        XCTAssertNil(message.syncError)
        XCTAssertNil(message.lastSyncedAt)
        XCTAssertNil(message.lastConfirmedAt)
    }

    // MARK: - Conversation persistence

    func testConversationPersistsMessagesInSequenceOrder() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let conversation = Conversation()
        context.insert(conversation)

        let first = Message(role: .user, content: "第一条", sequence: 0)
        first.conversation = conversation
        context.insert(first)

        let second = Message(role: .assistant, content: "回复", sequence: 1)
        second.conversation = conversation
        context.insert(second)

        let third = Message(role: .user, content: "第三条", sequence: 2)
        third.conversation = conversation
        context.insert(third)

        try context.save()

        // The relationship holds all three messages and exposes them in sequence order.
        XCTAssertEqual(conversation.messages.count, 3)
        XCTAssertEqual(conversation.sortedMessages.map(\.content), ["第一条", "回复", "第三条"])

        // A store fetch sorted by the explicit integer sequence reproduces the order.
        let descriptor = FetchDescriptor<Message>(sortBy: [SortDescriptor(\.sequence)])
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.map(\.content), ["第一条", "回复", "第三条"])
    }

    // MARK: - Cascade deletion

    func testDeletingConversationCascadesToMessagesAttachmentsAndBindings() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let conversation = Conversation()
        context.insert(conversation)

        let message = Message(role: .user, content: "带图消息", sequence: 0)
        message.conversation = conversation
        context.insert(message)

        let attachment = MessageAttachment(
            userOrder: 0,
            originalFileName: "photo.png",
            utType: "public.png",
            mimeType: "image/png",
            pixelWidth: 1200,
            pixelHeight: 800,
            fileSize: 102_400,
            relativePath: "attachments/photo.png"
        )
        attachment.message = message
        context.insert(attachment)

        let binding = NotionPageBinding(databaseID: "db_1", pageID: "page_1", createdAt: .now)
        binding.conversation = conversation
        context.insert(binding)

        try context.save()

        context.delete(conversation)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<Message>()), [])
        XCTAssertEqual(try context.fetch(FetchDescriptor<MessageAttachment>()), [])
        XCTAssertEqual(try context.fetch(FetchDescriptor<NotionPageBinding>()), [])
    }

    func testDeletionCoordinatorCancelsSyncAndRemovesConversationAttachments() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let conversation = Conversation()
        context.insert(conversation)
        try context.save()

        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let attachmentDirectory = root.appending(path: conversation.id.uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: attachmentDirectory, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: attachmentDirectory.appending(path: "photo.png"))

        let scheduler = RecordingScheduler()
        let coordinator = ConversationDeletionCoordinator(
            context: context,
            scheduler: scheduler,
            attachmentStore: AttachmentStore(rootURL: root)
        )

        await coordinator.delete(conversation: conversation)

        XCTAssertEqual(scheduler.cancelledConversationIDs, [conversation.id])
        XCTAssertTrue(try context.fetch(FetchDescriptor<Conversation>()).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: attachmentDirectory.path))
    }

    // MARK: - Settings defaults

    func testSettingsDefaultToOpenAICompatibleEndpoint() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let settings = AppSettings()

        XCTAssertEqual(settings.endpoint, "https://api.openai.com/v1/chat/completions")
        XCTAssertTrue(settings.supportsVision)
        XCTAssertNil(settings.maxImageBytes)
        XCTAssertNil(settings.maxRequestBodyBytes)
        XCTAssertFalse(settings.notionEnabled)
        XCTAssertNil(settings.notionDatabaseID)

        context.insert(settings)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<AppSettings>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.endpoint, "https://api.openai.com/v1/chat/completions")
    }

    // MARK: - Notion binding invariant

    func testConversationKeepsExactlyOneActivePageBinding() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let conversation = Conversation()
        context.insert(conversation)

        let earlier = Date(timeIntervalSince1970: 1_000)
        let later = Date(timeIntervalSince1970: 2_000)

        let first = conversation.bindNotionPage(databaseID: "db_1", pageID: "page_1", at: earlier)
        let second = conversation.bindNotionPage(databaseID: "db_2", pageID: "page_2", at: later)
        context.insert(first)
        context.insert(second)
        try context.save()

        XCTAssertEqual(conversation.pageBindings.count, 2)
        XCTAssertEqual(conversation.pageBindings.filter(\.isCurrent).count, 1)
        XCTAssertEqual(conversation.activePageBinding?.pageID, "page_2")
        XCTAssertTrue(conversation.activePageBinding?.databaseID == "db_2")
        XCTAssertFalse(first.isCurrent)
        XCTAssertTrue(second.isCurrent)
    }

    // MARK: - Title checkpoint fields

    func testTitleFlagsPersist() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let conversation = Conversation(title: "初始标题")
        conversation.titleGenerationAttempted = true
        context.insert(conversation)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Conversation>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.title, "初始标题")
        XCTAssertTrue(fetched.first?.titleGenerationAttempted == true)
        XCTAssertFalse(fetched.first?.isTitleManuallyEdited == true)
    }

    // MARK: - Message checkpoint mutation

    func testConfirmBatchAdvancesCursorAndStoresRemoteIDs() {
        let message = Message(role: .assistant, content: "回复", sequence: 1)
        let date = Date(timeIntervalSince1970: 5_000)
        message.confirmBatch(index: 0, blockIDs: ["block-1", "block-2"], at: date)

        XCTAssertEqual(message.nextNotionBatchIndex, 1)
        XCTAssertEqual(message.confirmedBatchIDs, ["0"])
        XCTAssertEqual(message.confirmedBlockIDs, ["block-1", "block-2"])
        XCTAssertEqual(message.lastConfirmedAt, date)

        // A second confirmed batch advances the cursor again.
        message.confirmBatch(index: 1, blockIDs: ["block-3"], at: date.addingTimeInterval(10))
        XCTAssertEqual(message.nextNotionBatchIndex, 2)
        XCTAssertEqual(message.confirmedBatchIDs, ["0", "1"])
        XCTAssertEqual(message.confirmedBlockIDs, ["block-1", "block-2", "block-3"])
    }
}

private final class RecordingScheduler: NotionSyncScheduling, @unchecked Sendable {
    private(set) var cancelledConversationIDs: [UUID] = []

    func enqueue(messageID: UUID) {}

    func cancel(conversationID: UUID) {
        cancelledConversationIDs.append(conversationID)
    }
}
