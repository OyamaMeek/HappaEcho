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
        XCTAssertEqual(operations.filter { $0 != "update:page" }, ["create:database", "list:page", "append:page"])
        XCTAssertEqual(fixture.conversation.activePageBinding?.databaseID, "database")
        XCTAssertEqual(fixture.message.nextNotionBatchIndex, 1)
        XCTAssertEqual(fixture.message.confirmedBatchIDs, ["0"])
    }

    func testExistingRemoteMarkerIsConfirmedWithoutDuplicateAppend() async throws {
        let fixture = try Fixture(enabled: true)
        let marker = "happaecho-message:\(fixture.message.id.uuidString.lowercased()):batch:0"
        await fixture.service.setListedBlocks([
            .init(kind: .paragraph, richText: [.init(content: marker)], markerMessageID: nil, remoteID: "remote-marker")
        ])

        await fixture.coordinator.enqueue(messageID: fixture.message.id)
        try await fixture.waitFor { fixture.message.syncState == .synced }

        let operations = await fixture.service.recordedOperations()
        XCTAssertEqual(operations.filter { $0 != "update:page" }, ["create:database", "list:page"])
        XCTAssertEqual(fixture.message.nextNotionBatchIndex, 1)
        XCTAssertEqual(fixture.message.confirmedBatchIDs, ["0"])
        XCTAssertEqual(fixture.message.confirmedBlockIDs, ["remote-marker"])
    }

    func testCancelDoesNotStartAnotherWorkerBeforeOriginalExits() async throws {
        let fixture = try Fixture(enabled: true)
        await fixture.service.blockNextAppend()
        await fixture.coordinator.enqueue(messageID: fixture.message.id)
        for _ in 0..<100 where await fixture.service.appendCallCount() == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }

        await fixture.coordinator.cancel(conversationID: fixture.conversation.id)
        await fixture.coordinator.enqueue(messageID: fixture.message.id)
        let beforeRelease = await fixture.service.appendCallCount()
        XCTAssertEqual(beforeRelease, 1)

        await fixture.service.releaseAppend()
        try await fixture.waitFor { fixture.message.syncState == .synced }
        let calls = await fixture.service.appendCallCount()
        XCTAssertEqual(calls, 2)
    }

    func testMetadataWorkUpdatesExistingPageProperties() async throws {
        let fixture = try Fixture(enabled: true)
        fixture.conversation.bindNotionPage(databaseID: "database", pageID: "page")
        try fixture.context.save()

        await fixture.coordinator.enqueueMetadata(conversationID: fixture.conversation.id)
        for _ in 0..<100 {
            if await fixture.service.recordedOperations().contains("update:page") { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        let operations = await fixture.service.recordedOperations()
        XCTAssertEqual(operations, ["update:page"])
    }

    func testSyncUploadsAttachmentAndAppendsImageBlock() async throws {
        let fixture = try Fixture(enabled: true, withAttachment: true)

        await fixture.coordinator.enqueue(messageID: fixture.message.id)
        try await fixture.waitFor { fixture.message.syncState == .synced }

        let operations = await fixture.service.recordedOperations()
        XCTAssertEqual(operations.filter { $0 != "update:page" }, ["create:database", "list:page", "append:page", "upload:create:image.png", "upload:send:upload", "upload:complete:upload", "list:page", "append:page"])
        let attachment = try XCTUnwrap(fixture.message.attachments.first)
        XCTAssertEqual(attachment.notionUploadID, "upload")
        XCTAssertNotNil(attachment.notionUploadSentAt)
        XCTAssertEqual(attachment.notionRemoteURL, "https://files.example.test/image.png")
        XCTAssertEqual(attachment.notionImageBlockID, "image-block")
        XCTAssertEqual(attachment.syncState, .synced)
    }

    func testRecoveryResendsPendingUploadAfterFailedSendIntent() async throws {
        let fixture = try Fixture(enabled: true, withAttachment: true)
        await fixture.service.failNextSend()

        await fixture.coordinator.enqueue(messageID: fixture.message.id)
        try await fixture.waitFor { fixture.message.syncState == .failed }

        await fixture.coordinator.enqueue(messageID: fixture.message.id)
        try await fixture.waitFor { fixture.message.syncState == .synced }

        let sendCalls = await fixture.service.sendCallCount()
        let retrieveCalls = await fixture.service.retrieveCallCount()
        XCTAssertEqual(sendCalls, 2)
        XCTAssertEqual(retrieveCalls, 1)
    }

    func testRecoverySkipsResendWhenRemoteUploadAlreadyCompleted() async throws {
        let fixture = try Fixture(enabled: true, withAttachment: true)
        await fixture.service.failNextSend()
        await fixture.service.setRetrievedUploadStatus("uploaded")

        await fixture.coordinator.enqueue(messageID: fixture.message.id)
        try await fixture.waitFor { fixture.message.syncState == .failed }

        await fixture.coordinator.enqueue(messageID: fixture.message.id)
        try await fixture.waitFor { fixture.message.syncState == .synced }

        let sendCalls = await fixture.service.sendCallCount()
        let retrieveCalls = await fixture.service.retrieveCallCount()
        let completeCalls = await fixture.service.completeCallCount()
        XCTAssertEqual(sendCalls, 1)
        XCTAssertEqual(retrieveCalls, 1)
        XCTAssertEqual(completeCalls, 0)
    }

    @MainActor
    private final class Fixture {
        let container: ModelContainer
        let context: ModelContext
        let conversation: Conversation
        let message: Message
        let service = FakeNotionService()
        let attachmentDirectoryURL: URL?
        let store: SwiftDataNotionSyncModelStore
        let coordinator: NotionSyncCoordinator

        init(enabled: Bool, withAttachment: Bool = false) throws {
            container = try HappaEchoSchema.makeContainer(inMemory: true)
            context = container.mainContext
            let settings = AppSettings(notionEnabled: enabled, notionDatabaseID: "database")
            conversation = Conversation(title: "Chat")
            message = Message(role: .user, content: "Hello", sequence: 0)
            message.conversation = conversation
            if withAttachment {
                let attachmentRootURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appending(path: "HappaEcho/Attachments", directoryHint: .isDirectory)
                let relativePath = "\(conversation.id.uuidString)/image.png"
                let fileURL = attachmentRootURL.appending(path: relativePath)
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data([0x89]).write(to: fileURL)
                attachmentDirectoryURL = fileURL.deletingLastPathComponent()
                let attachment = MessageAttachment(userOrder: 0, originalFileName: "image.png", utType: "public.png", mimeType: "image/png", pixelWidth: 1, pixelHeight: 1, fileSize: 1, relativePath: relativePath)
                attachment.message = message
                message.attachments.append(attachment)
                context.insert(attachment)
            } else {
                attachmentDirectoryURL = nil
            }
            context.insert(settings)
            context.insert(conversation)
            context.insert(message)
            try context.save()
            store = SwiftDataNotionSyncModelStore(modelContext: context)
            coordinator = NotionSyncCoordinator(service: service, store: store, sleeper: ImmediateNotionSyncSleeper())
        }

        deinit {
            if let attachmentDirectoryURL {
                try? FileManager.default.removeItem(at: attachmentDirectoryURL)
            }
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
    var listedBlocks: [NotionBlock] = []
    var appendCalls = 0
    var appendBlocked = false
    var appendContinuation: CheckedContinuation<Void, Never>?
    var sendCalls = 0
    var retrieveCalls = 0
    var completeCalls = 0
    var retrievedUploadStatus = "pending"
    var shouldFailNextSend = false

    func recordedOperations() -> [String] { operations }
    func setListedBlocks(_ blocks: [NotionBlock]) { listedBlocks = blocks }
    func blockNextAppend() { appendBlocked = true }
    func appendCallCount() -> Int { appendCalls }
    func sendCallCount() -> Int { sendCalls }
    func retrieveCallCount() -> Int { retrieveCalls }
    func completeCallCount() -> Int { completeCalls }
    func failNextSend() { shouldFailNextSend = true }
    func setRetrievedUploadStatus(_ status: String) { retrievedUploadStatus = status }
    func releaseAppend() { appendBlocked = false; appendContinuation?.resume(); appendContinuation = nil }

    func createPage(_ request: NotionPageRequest) async throws -> NotionPage {
        operations.append("create:\(request.databaseID)")
        return NotionPage(id: "page", url: nil)
    }

    func updatePageProperties(pageID: String, properties: [String: NotionProperty]) async throws {
        operations.append("update:\(pageID)")
    }

    func appendBlocks(pageID: String, blocks: [NotionBlock]) async throws -> [String] {
        appendCalls += 1
        operations.append("append:\(pageID)")
        if appendBlocked {
            await withCheckedContinuation { appendContinuation = $0 }
        }
        if blocks.contains(where: {
            if case .image = $0.kind { return true }
            return false
        }) { return ["image-block"] }
        return blocks.indices.map { "block-\($0)" }
    }

    func listBlocks(pageID: String, cursor: String?) async throws -> NotionBlockPage {
        operations.append("list:\(pageID)")
        return .init(blocks: listedBlocks, hasMore: false, nextCursor: nil)
    }

    func createFileUpload(_ request: NotionFileUploadRequest) async throws -> NotionFileUpload {
        operations.append("upload:create:\(request.filename)")
        return NotionFileUpload(id: "upload", status: "pending", file: nil)
    }

    func retrieveFileUpload(uploadID: String) async throws -> NotionFileUpload {
        retrieveCalls += 1
        operations.append("upload:retrieve:\(uploadID)")
        let file = retrievedUploadStatus == "uploaded"
            ? NotionFileUpload.File(url: URL(string: "https://files.example.test/image.png"))
            : nil
        return NotionFileUpload(id: uploadID, status: retrievedUploadStatus, file: file)
    }

    func sendFile(uploadID: String, fileURL: URL, contentType: String) async throws {
        _ = try Data(contentsOf: fileURL)
        sendCalls += 1
        operations.append("upload:send:\(uploadID)")
        if shouldFailNextSend {
            shouldFailNextSend = false
            throw NotionError.network(code: URLError.cannotConnectToHost.rawValue)
        }
    }

    func completeFileUpload(uploadID: String) async throws -> NotionFileUpload {
        completeCalls += 1
        operations.append("upload:complete:\(uploadID)")
        return NotionFileUpload(id: uploadID, status: "uploaded", file: .init(url: URL(string: "https://files.example.test/image.png")))
    }
}
