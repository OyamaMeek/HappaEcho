import XCTest
import SwiftData
@testable import HappaEcho

@MainActor
final class NotionSyncCoordinatorTests: XCTestCase {
    func testDisabledSettingsLeaveQueuedMessagePendingWithoutNetworkWork() async throws {
        let fixture = try Fixture(enabled: false)
        await fixture.coordinator.enqueue(messageID: fixture.message.id)
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(fixture.message.syncState, .pending)
        let operations = await fixture.service.recordedOperations()
        XCTAssertTrue(operations.isEmpty)
    }

    func testSyncCreatesPageAndConfirmsDeterministicBatch() async throws {
        let fixture = try Fixture(enabled: true)
        await fixture.coordinator.enqueue(messageID: fixture.message.id)
        try await fixture.waitFor { fixture.message.syncState == .synced }

        let operations = await fixture.service.recordedOperations()
        XCTAssertEqual(operations, ["create:database", "append:page"])
        XCTAssertEqual(fixture.conversation.activePageBinding?.databaseID, "database")
        XCTAssertEqual(fixture.message.nextNotionBatchIndex, 1)
        XCTAssertEqual(fixture.message.confirmedBatchIDs, ["0"])
    }

    @MainActor
    private final class Fixture {
        let container: ModelContainer
        let context: ModelContext
        let conversation: Conversation
        let message: Message
        let service = FakeNotionService()
        let store: SwiftDataNotionSyncModelStore
        let coordinator: NotionSyncCoordinator

        init(enabled: Bool) throws {
            container = try HappaEchoSchema.makeContainer(inMemory: true)
            context = container.mainContext
            let settings = AppSettings(notionEnabled: enabled, notionDatabaseID: "database")
            conversation = Conversation(title: "Chat")
            message = Message(role: .user, content: "Hello", sequence: 0)
            message.conversation = conversation
            context.insert(settings)
            context.insert(conversation)
            context.insert(message)
            try context.save()
            store = SwiftDataNotionSyncModelStore(modelContext: context)
            coordinator = NotionSyncCoordinator(service: service, store: store, sleeper: ImmediateNotionSyncSleeper())
        }

        func waitFor(_ predicate: @escaping () -> Bool) async throws {
            for _ in 0..<100 {
                if predicate() { return }
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTFail("timed out waiting for sync")
        }
    }
}

actor FakeNotionService: NotionService {
    var operations: [String] = []

    func recordedOperations() -> [String] { operations }

    func createPage(_ request: NotionPageRequest) async throws -> NotionPage {
        operations.append("create:\(request.databaseID)")
        return NotionPage(id: "page", url: nil)
    }

    func updatePageProperties(pageID: String, properties: [String: NotionProperty]) async throws {}

    func appendBlocks(pageID: String, blocks: [NotionBlock]) async throws -> [String] {
        operations.append("append:\(pageID)")
        return blocks.indices.map { "block-\($0)" }
    }

    func listBlocks(pageID: String, cursor: String?) async throws -> NotionBlockPage {
        .init(blocks: [], hasMore: false, nextCursor: nil)
    }

    func createFileUpload(_ request: NotionFileUploadRequest) async throws -> NotionFileUpload {
        NotionFileUpload(id: "upload", status: "pending", file: nil)
    }

    func sendFile(uploadID: String, fileURL: URL, contentType: String) async throws {}

    func completeFileUpload(uploadID: String) async throws -> NotionFileUpload {
        NotionFileUpload(id: uploadID, status: "uploaded", file: nil)
    }
}
