import XCTest
import SwiftData
@testable import HappaEcho

@MainActor
final class TitleGenerationCoordinatorTests: XCTestCase {
    func testStoppedFallbackLeavesLaterCompletedEligible() async throws {
        let fixture = try Fixture()
        let user = fixture.add(.user, "First question")
        let stopped = fixture.add(.assistant, "partial", state: .stopped)
        await fixture.coordinator.generateIfEligible(for: fixture.conversation)
        XCTAssertEqual(fixture.conversation.title, "First question")
        XCTAssertEqual(fixture.service.requests.count, 0)
        let completed = fixture.add(.assistant, "complete", state: .completed)
        await fixture.coordinator.generateIfEligible(for: fixture.conversation)
        XCTAssertEqual(fixture.service.requests.count, 1)
        XCTAssertEqual(fixture.conversation.title, "Model title")
        _ = (user, stopped, completed)
    }

    func testOnlyFirstCompletedResponseStartsOneRequest() async throws {
        let fixture = try Fixture()
        fixture.add(.user, "Question")
        fixture.add(.assistant, "answer", state: .completed)
        await fixture.coordinator.generateIfEligible(for: fixture.conversation)
        fixture.add(.assistant, "second", state: .completed)
        await fixture.coordinator.generateIfEligible(for: fixture.conversation)
        XCTAssertEqual(fixture.service.requests.count, 1)
    }

    func testNormalizesQuotesNewlinesAndTruncatesByCharacters() async throws {
        let fixture = try Fixture()
        fixture.service.result = "\"一\n二\n三\n四\n五\n六\n七\n八\n九\n十\n十一\n十二\n十三\n十四\n十五\n十六\n十七\n十八\n十九\n二十\n二十一\n二十二\n二十三\n二十四\n二十五\n二十六\n二十七\n二十八\n二十九\n三十\n三十一\""
        fixture.add(.user, "Question")
        fixture.add(.assistant, "answer", state: .completed)
        await fixture.coordinator.generateIfEligible(for: fixture.conversation)
        XCTAssertEqual(fixture.conversation.title.count, 30)
        XCTAssertFalse(fixture.conversation.title.contains("\n"))
        XCTAssertFalse(fixture.conversation.title.hasPrefix("\""))
    }

    func testCompletedGenerationFailurePreservesFallbackAndEnqueuesOnce() async throws {
        let fixture = try Fixture()
        fixture.service.shouldThrow = true
        fixture.add(.user, "Fallback title")
        fixture.add(.assistant, "answer", state: .completed)
        await fixture.coordinator.generateIfEligible(for: fixture.conversation)
        XCTAssertEqual(fixture.conversation.title, "Fallback title")
        XCTAssertEqual(fixture.scheduler.metadataUpdates, [fixture.conversation.id])
    }
    func testFailureKeepsFallbackAndManualEditWinsDuringGeneration() async throws {
        let fixture = try Fixture()
        fixture.service.block = true
        fixture.add(.user, "Fallback")
        fixture.add(.assistant, "answer", state: .completed)
        let task = Task { await fixture.coordinator.generateIfEligible(for: fixture.conversation) }
        await fixture.service.waitUntilRequested()
        try await fixture.coordinator.setManualTitle("Manual", for: fixture.conversation)
        fixture.service.resume()
        await task.value
        XCTAssertEqual(fixture.conversation.title, "Manual")
        XCTAssertTrue(fixture.conversation.isTitleManuallyEdited)
    }


    private final class Fixture {
        let conversation = Conversation()
        let service = FakeTitleService()
        let scheduler = FakeScheduler()
        let context: ModelContext
        let coordinator: TitleGenerationCoordinator

        @MainActor init() throws {
            let container = try ModelContainer(for: Conversation.self, Message.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            context = ModelContext(container)
            context.insert(conversation)
            coordinator = TitleGenerationCoordinator(service: service, modelContext: context, syncScheduler: scheduler)

        }
        @discardableResult func add(_ role: MessageRole, _ content: String, state: GenerationState = .none) -> Message {
            let message = Message(role: role, content: content, sequence: conversation.messages.count, generationState: state)
            message.conversation = conversation; conversation.messages.append(message); context.insert(message); try? context.save(); return message
        }
    }

    private final class FakeTitleService: ChatCompletionService, @unchecked Sendable {
        var result = "Model title"; var block = false; var shouldThrow = false; private var requested = false; private var continuation: CheckedContinuation<Void, Never>?
        var requests = [TitleRequest]()
        func stream(request: ChatRequest) -> AsyncThrowingStream<String, Error> { AsyncThrowingStream { $0.finish() } }
        func generateTitle(request: TitleRequest) async throws -> String { requests.append(request); requested = true; continuation?.resume(); continuation = nil; if shouldThrow { throw ChatServiceError.serverError(message: "failed") }; if block { await withCheckedContinuation { continuation = $0 } }; return result }
        func waitUntilRequested() async { while !requested { await Task.yield() } }
        func resume() { continuation?.resume(); continuation = nil }
    }
    private final class FakeScheduler: TitleSyncScheduling {
        var metadataUpdates = [UUID]()
        func enqueueMetadata(conversationID: UUID) { metadataUpdates.append(conversationID) }
    }
}
