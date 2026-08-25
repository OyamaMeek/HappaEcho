import XCTest
import SwiftData
@testable import HappaEcho

@MainActor
final class ChatSessionControllerTests: XCTestCase {
    func testSendPersistsUserBeforeStreamingAndSchedulesIt() async throws {
        let fixture = try Fixture()
        fixture.service.streams = [.manual]

        await fixture.controller.send(text: "Hello", attachments: [], conversation: fixture.conversation)

        XCTAssertEqual(fixture.conversation.sortedMessages.map(\.content), ["Hello"])
        XCTAssertEqual(fixture.conversation.sortedMessages.map(\.sequence), [0])
        XCTAssertEqual(fixture.scheduler.enqueued, [fixture.conversation.sortedMessages[0].id])
    }

    func testRequestContainsEachPersistedMessageOnceInSequenceOrder() async throws {
        let fixture = try Fixture()
        fixture.add(role: .user, content: "Earlier", sequence: 3)
        fixture.add(role: .assistant, content: "Reply", sequence: 8)
        fixture.service.streams = [.manual]

        await fixture.controller.send(text: "Latest", attachments: [], conversation: fixture.conversation)

        XCTAssertEqual(fixture.service.requests[0].messages, [
            ChatInputMessage(role: .user, content: [.text("Earlier")]),
            ChatInputMessage(role: .assistant, content: [.text("Reply")]),
            ChatInputMessage(role: .user, content: [.text("Latest")])
        ])
        XCTAssertEqual(fixture.conversation.sortedMessages.map(\.sequence), [3, 8, 9])
    }

    func testSupportedVisionRequestIncludesAttachmentsInUserOrder() async throws {
        let fixture = try Fixture()
        let later = try await fixture.importedAttachment(named: "later.png", order: 1)
        let earlier = try await fixture.importedAttachment(named: "earlier.png", order: 0)
        fixture.service.streams = [.manual]

        await fixture.controller.send(text: "Picture", attachments: [later, earlier], conversation: fixture.conversation)

        XCTAssertEqual(fixture.service.requests[0].messages, [
            ChatInputMessage(role: .user, content: [
                .text("Picture"),
                .image(.init(mimeType: "image/png", base64: "AQID")),
                .image(.init(mimeType: "image/png", base64: "BAUG"))
            ])
        ])
    }

    func testDuplicatePersistedSequenceBlocksDispatch() async throws {
        let fixture = try Fixture()
        fixture.add(role: .user, content: "One", sequence: 0)
        fixture.add(role: .assistant, content: "Two", sequence: 0)
        fixture.service.streams = [.manual]

        await fixture.controller.send(text: "Three", attachments: [], conversation: fixture.conversation)

        XCTAssertEqual(fixture.service.requests.count, 0)
        XCTAssertEqual(fixture.controller.state(for: fixture.conversation.id), .failed(message: "Message sequence invariant violated"))
    }

    func testRejectsSecondGenerationForSameConversation() async throws {
        let fixture = try Fixture()
        fixture.service.streams = [.manual]
        await fixture.controller.send(text: "First", attachments: [], conversation: fixture.conversation)
        await fixture.controller.send(text: "Second", attachments: [], conversation: fixture.conversation)

        XCTAssertEqual(fixture.service.requests.count, 1)
        XCTAssertEqual(fixture.conversation.sortedMessages.map(\.content), ["First"])
    }

    func testCompletedStreamPersistsAssistantExactlyOnceAndSchedulesIt() async throws {
        let fixture = try Fixture()
        fixture.service.streams = [.deltas(["A", "B"])]
        await fixture.controller.send(text: "Question", attachments: [], conversation: fixture.conversation)
        try await fixture.waitForTerminal()

        XCTAssertEqual(fixture.conversation.sortedMessages.map { ($0.role, $0.content, $0.generationState) }.count, 2)
        XCTAssertEqual(fixture.conversation.sortedMessages[1].content, "AB")
        XCTAssertEqual(fixture.conversation.sortedMessages[1].generationState, .completed)
        XCTAssertEqual(fixture.scheduler.enqueued.count, 2)
    }

    func testStoppingBeforeAnyDeltaDoesNotPersistAssistant() async throws {
        let fixture = try Fixture()
        fixture.service.streams = [.manual]
        await fixture.controller.send(text: "Question", attachments: [], conversation: fixture.conversation)
        fixture.controller.stop(conversationID: fixture.conversation.id)
        try await fixture.waitForTerminal()

        XCTAssertEqual(fixture.conversation.sortedMessages.count, 1)
        XCTAssertEqual(fixture.controller.state(for: fixture.conversation.id), .idle)
    }

    func testStoppingAfterContentPersistsStoppedAssistant() async throws {
        let fixture = try Fixture()
        let stream = ControlledStream()
        fixture.service.streams = [.controlled(stream)]
        await fixture.controller.send(text: "Question", attachments: [], conversation: fixture.conversation)
        stream.yield("Partial")
        try await Task.sleep(for: .milliseconds(20))
        fixture.controller.stop(conversationID: fixture.conversation.id)
        stream.finish()
        try await fixture.waitForTerminal()

        XCTAssertEqual(fixture.conversation.sortedMessages[1].content, "Partial")
        XCTAssertEqual(fixture.conversation.sortedMessages[1].generationState, .stopped)
    }

    func testEmptyFailureDoesNotPersistAssistant() async throws {
        let fixture = try Fixture()
        fixture.service.streams = [.failure(TestError.boom)]
        await fixture.controller.send(text: "Question", attachments: [], conversation: fixture.conversation)
        try await fixture.waitForTerminal()

        XCTAssertEqual(fixture.conversation.sortedMessages.count, 1)
        XCTAssertEqual(fixture.controller.state(for: fixture.conversation.id), .failed(message: "boom"))
    }

    func testPartialFailurePersistsAssistantAndMarksFailedPartial() async throws {
        let fixture = try Fixture()
        fixture.service.streams = [.deltasThenFailure(["Partial"], TestError.boom)]
        await fixture.controller.send(text: "Question", attachments: [], conversation: fixture.conversation)
        try await fixture.waitForTerminal()

        XCTAssertEqual(fixture.conversation.sortedMessages[1].content, "Partial")
        XCTAssertEqual(fixture.conversation.sortedMessages[1].generationState, .failedPartial)
    }

    func testContinuationIncludesPriorImageAndSavedPartialAssistantExactlyOnce() async throws {
        let fixture = try Fixture()
        let image = try await fixture.importedAttachment(named: "earlier.png", order: 0)
        let user = fixture.add(role: .user, content: "Question", sequence: 0)
        image.message = user
        user.attachments.append(image)
        let partial = fixture.add(role: .assistant, content: "Partial", sequence: 1, generationState: .failedPartial)
        fixture.service.streams = [.manual]

        await fixture.controller.continueGeneration(after: partial, in: fixture.conversation)

        XCTAssertEqual(fixture.service.requests[0].messages, [
            ChatInputMessage(role: .user, content: [
                .text("Question"),
                .image(.init(mimeType: "image/png", base64: "AQID"))
            ]),
            ChatInputMessage(role: .assistant, content: [.text("Partial")])
        ])
    }

    func testContinuationWithDuplicateSequenceBlocksDispatch() async throws {
        let fixture = try Fixture()
        fixture.add(role: .user, content: "Question", sequence: 0)
        let partial = fixture.add(role: .assistant, content: "Partial", sequence: 0, generationState: .failedPartial)
        fixture.service.streams = [.manual]

        await fixture.controller.continueGeneration(after: partial, in: fixture.conversation)

        XCTAssertTrue(fixture.service.requests.isEmpty)
        XCTAssertEqual(fixture.controller.state(for: fixture.conversation.id), .failed(message: "Message sequence invariant violated"))
    }

    func testOtherConversationGenerationContinuesWhileSecondConversationSends() async throws {
        let fixture = try Fixture()
        let other = Conversation(modelID: "model")
        fixture.context.insert(other)
        let firstStream = ControlledStream()
        fixture.service.streams = [.controlled(firstStream), .manual]

        await fixture.controller.send(text: "First", attachments: [], conversation: fixture.conversation)
        await fixture.controller.send(text: "Second", attachments: [], conversation: other)
        XCTAssertEqual(fixture.controller.state(for: fixture.conversation.id), .generating(text: ""))
        XCTAssertEqual(fixture.controller.state(for: other.id), .generating(text: ""))

        firstStream.yield("Done")
        firstStream.finish()
        try await fixture.waitForTerminal(conversation: fixture.conversation)
        XCTAssertEqual(other.isGenerating, true)
    }

    func testUnsupportedVisionLeavesDraftUnpersisted() async throws {
        let fixture = try Fixture(supportsVision: false)
        let attachment = MessageAttachment(userOrder: 0, originalFileName: "a.png", utType: "public.png", mimeType: "image/png", pixelWidth: 1, pixelHeight: 1, fileSize: 1, relativePath: "a.png")

        let wasAccepted = await fixture.controller.send(text: "Picture", attachments: [attachment], conversation: fixture.conversation)

        XCTAssertFalse(wasAccepted)
        XCTAssertTrue(fixture.conversation.messages.isEmpty)
        XCTAssertEqual(fixture.controller.state(for: fixture.conversation.id), .blocked(.unsupportedVision))
    }

    func testContextLimitRestoresDraft() async throws {
        let fixture = try Fixture()
        fixture.service.streams = [.failure(ChatServiceError.invalidRequest(message: "maximum context length exceeded"))]
        let attachment = MessageAttachment(userOrder: 0, originalFileName: "a.png", utType: "public.png", mimeType: "image/png", pixelWidth: 1, pixelHeight: 1, fileSize: 1, relativePath: "a.png")

        await fixture.controller.send(text: "Draft", attachments: [attachment], conversation: fixture.conversation)
        try await fixture.waitForTerminal()

        XCTAssertEqual(fixture.controller.restoredDraft(for: fixture.conversation.id)?.text, "Draft")
        XCTAssertEqual(fixture.controller.restoredDraft(for: fixture.conversation.id)?.attachments.count, 1)
        XCTAssertEqual(fixture.conversation.sortedMessages.count, 1)
    }

    func testContextLimitRetryReusesPersistedUserTurnWithoutDuplication() async throws {
        let fixture = try Fixture()
        let attachment = try await fixture.importedAttachment(named: "earlier.png", order: 0)
        fixture.service.streams = [
            .failure(ChatServiceError.invalidRequest(message: "maximum context length exceeded")),
            .manual
        ]

        await fixture.controller.send(text: "Draft", attachments: [attachment], conversation: fixture.conversation)
        try await fixture.waitForTerminal()
        await fixture.controller.retryRestoredDraft(in: fixture.conversation)

        XCTAssertEqual(fixture.conversation.sortedMessages.count, 1)
        XCTAssertEqual(fixture.service.requests.count, 2)
        XCTAssertEqual(fixture.service.requests[1].messages, [
            ChatInputMessage(role: .user, content: [
                .text("Draft"),
                .image(.init(mimeType: "image/png", base64: "AQID"))
            ])
        ])
    }

    func testStreamingStatePublishesDeltas() async throws {
        let fixture = try Fixture()
        let stream = ControlledStream()
        fixture.service.streams = [.controlled(stream)]
        await fixture.controller.send(text: "Question", attachments: [], conversation: fixture.conversation)
        stream.yield("Delta")
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(fixture.controller.state(for: fixture.conversation.id), .generating(text: "Delta"))
    }
}

@MainActor private final class Fixture {
    let context: ModelContext
    let conversation: Conversation
    let service = FakeChatService()
    let scheduler = FakeSyncScheduler()
    let attachmentRoot: URL
    let controller: ChatSessionController

    init(supportsVision: Bool = true) throws {
        let container = try HappaEchoSchema.makeContainer(inMemory: true)
        context = ModelContext(container)
        attachmentRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        conversation = Conversation(modelID: "model")
        context.insert(conversation)
        controller = ChatSessionController(service: service, modelContext: context, attachmentStore: AttachmentStore(rootURL: attachmentRoot), syncScheduler: scheduler, settings: ChatSessionSettings(modelID: "model", supportsVision: supportsVision))
    }

    @discardableResult func add(role: MessageRole, content: String, sequence: Int, generationState: GenerationState = .none) -> Message {
        let message = Message(role: role, content: content, sequence: sequence, generationState: generationState)
        message.conversation = conversation
        conversation.messages.append(message)
        context.insert(message)
        return message
    }

    func waitForTerminal(conversation: Conversation? = nil) async throws {
        let conversation = conversation ?? self.conversation
        for _ in 0..<100 {
            if !conversation.isGenerating { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("generation did not finish")
    }

    func importedAttachment(named name: String, order: Int) async throws -> MessageAttachment {
        let directory = attachmentRoot.appending(path: conversation.id.uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = "\(conversation.id.uuidString)/\(name)"
        let data: Data = name == "earlier.png" ? Data([1, 2, 3]) : Data([4, 5, 6])
        try data.write(to: attachmentRoot.appending(path: path))
        return MessageAttachment(userOrder: order, originalFileName: name, utType: "public.png", mimeType: "image/png", pixelWidth: 1, pixelHeight: 1, fileSize: data.count, relativePath: path)
    }
}

private final class FakeSyncScheduler: NotionSyncScheduling, @unchecked Sendable {
    var enqueued: [UUID] = []
    func enqueue(messageID: UUID) { enqueued.append(messageID) }
    func cancel(conversationID: UUID) {}
}

private final class FakeChatService: ChatCompletionService {
    enum Script { case manual, controlled(ControlledStream), deltas([String]), failure(Error), deltasThenFailure([String], Error) }
    var streams: [Script] = []
    var requests: [ChatRequest] = []
    func stream(request: ChatRequest) -> AsyncThrowingStream<String, Error> {
        requests.append(request)
        guard !streams.isEmpty else { return AsyncThrowingStream { $0.finish() } }
        let script = streams.removeFirst()
        switch script {
        case .manual: return AsyncThrowingStream { _ in }
        case .controlled(let stream): return stream.stream
        case .deltas(let values): return AsyncThrowingStream { continuation in
            for value in values { continuation.yield(value) }
            continuation.finish()
        }
        case .failure(let error): return AsyncThrowingStream { continuation in continuation.finish(throwing: error) }
        case .deltasThenFailure(let values, let error): return AsyncThrowingStream { continuation in
            for value in values { continuation.yield(value) }
            continuation.finish(throwing: error)
        }
        }
    }
    func generateTitle(request: TitleRequest) async throws -> String { "" }
}

private final class ControlledStream: @unchecked Sendable {
    private var continuation: AsyncThrowingStream<String, Error>.Continuation?
    lazy var stream = AsyncThrowingStream<String, Error> { self.continuation = $0 }
    func yield(_ value: String) { continuation?.yield(value) }
    func finish() { continuation?.finish() }
}

private enum TestError: LocalizedError { case boom; var errorDescription: String? { "boom" } }
