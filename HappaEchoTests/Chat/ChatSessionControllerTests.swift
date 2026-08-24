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

    func testContinuationIncludesSavedPartialAssistantExactlyOnce() async throws {
        let fixture = try Fixture()
        let partial = fixture.add(role: .assistant, content: "Partial", sequence: 1, generationState: .failedPartial)
        fixture.service.streams = [.manual]

        await fixture.controller.continueGeneration(after: partial, in: fixture.conversation)

        XCTAssertEqual(fixture.service.requests[0].messages, [
            ChatInputMessage(role: .assistant, content: [.text("Partial")])
        ])
    }

    func testConversationSwitchDoesNotCancelOtherConversation() async throws {
        let fixture = try Fixture()
        let other = Conversation(modelID: "model")
        fixture.context.insert(other)
        fixture.service.streams = [.deltas(["Done"])]

        await fixture.controller.send(text: "Question", attachments: [], conversation: fixture.conversation)
        try await fixture.waitForTerminal()

        XCTAssertEqual(fixture.conversation.sortedMessages.count, 2)
        XCTAssertEqual(other.isGenerating, false)
    }

    func testUnsupportedVisionLeavesDraftUnpersisted() async throws {
        let fixture = try Fixture(supportsVision: false)
        let attachment = MessageAttachment(userOrder: 0, originalFileName: "a.png", utType: "public.png", mimeType: "image/png", pixelWidth: 1, pixelHeight: 1, fileSize: 1, relativePath: "a.png")

        await fixture.controller.send(text: "Picture", attachments: [attachment], conversation: fixture.conversation)

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
    }
}

@MainActor private final class Fixture {
    let context: ModelContext
    let conversation: Conversation
    let service = FakeChatService()
    let scheduler = FakeSyncScheduler()
    let controller: ChatSessionController

    init(supportsVision: Bool = true) throws {
        let container = try HappaEchoSchema.makeContainer(inMemory: true)
        context = ModelContext(container)
        conversation = Conversation(modelID: "model")
        context.insert(conversation)
        controller = ChatSessionController(service: service, modelContext: context, attachmentStore: AttachmentStore(rootURL: FileManager.default.temporaryDirectory), syncScheduler: scheduler, settings: ChatSessionSettings(modelID: "model", supportsVision: supportsVision))
    }

    @discardableResult func add(role: MessageRole, content: String, sequence: Int, generationState: GenerationState = .none) -> Message {
        let message = Message(role: role, content: content, sequence: sequence, generationState: generationState)
        message.conversation = conversation
        conversation.messages.append(message)
        context.insert(message)
        return message
    }

    func waitForTerminal() async throws {
        for _ in 0..<100 {
            if !conversation.isGenerating { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("generation did not finish")
    }
}

private final class FakeSyncScheduler: NotionSyncScheduling, @unchecked Sendable {
    var enqueued: [UUID] = []
    func enqueue(messageID: UUID) { enqueued.append(messageID) }
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
