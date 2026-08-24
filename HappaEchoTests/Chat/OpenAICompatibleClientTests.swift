import XCTest
@testable import HappaEcho

/// URLProtocol stub that records the captured request and replays a canned
/// streaming response. Set `handler` before exercising the client; the response
/// is delivered as `didLoad` chunks so the streaming client sees real byte
/// fragmentation.
final class StubURLProtocol: URLProtocol {
    struct Response {
        var statusCode: Int = 200
        var headers: [String: String] = [:]
        var chunks: [Data] = []
        /// When false, `startLoading` delivers the chunks but never finishes,
        /// leaving the connection open until the task is cancelled.
        var finishImmediately: Bool = true
    }

    private static let stateLock = NSLock()
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> Response)?
    nonisolated(unsafe) static var capturedRequest: URLRequest?
    nonisolated(unsafe) static var stopLoadingCount = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.stateLock.lock()
        let handler = Self.handler
        Self.stateLock.unlock()
        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let response = try handler(request)
            Self.stateLock.lock()
            Self.capturedRequest = request
            Self.stateLock.unlock()
            guard let url = request.url else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            let headers = response.headers.isEmpty ? nil : response.headers
            let http = HTTPURLResponse(url: url, statusCode: response.statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            for chunk in response.chunks {
                client?.urlProtocol(self, didLoad: chunk)
            }
            if response.finishImmediately {
                client?.urlProtocolDidFinishLoading(self)
            }
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        Self.stateLock.lock()
        Self.stopLoadingCount += 1
        Self.stateLock.unlock()
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
    }
}

final class OpenAICompatibleClientTests: XCTestCase {
    private static let endpoint = URL(string: "https://example.test/v1/chat/completions")!

    override func tearDown() {
        StubURLProtocol.handler = nil
        StubURLProtocol.capturedRequest = nil
        StubURLProtocol.stopLoadingCount = 0
        super.tearDown()
    }

    private func makeClient() -> OpenAICompatibleClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        return OpenAICompatibleClient(
            configuration: .init(endpoint: Self.endpoint, apiKey: "sk-test"),
            session: session
        )
    }

    private func sampleRequest() -> ChatRequest {
        ChatRequest(model: "gpt-test", messages: [
            ChatInputMessage(role: .user, content: [.text("Hello")]),
        ])
    }

    private func titleRequest() -> TitleRequest {
        TitleRequest(model: "gpt-test", messages: [
            ChatInputMessage(role: .user, content: [.text("标题")]),
        ])
    }

    private func collect(_ stream: AsyncThrowingStream<String, Error>) async throws -> [String] {
        var pieces: [String] = []
        for try await piece in stream {
            pieces.append(piece)
        }
        return pieces
    }

    private func assertStreamError(
        _ expected: ChatServiceError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await collect(makeClient().stream(request: sampleRequest()))
            XCTFail("expected \(expected)", file: file, line: line)
        } catch let error as ChatServiceError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("unexpected error \(error)", file: file, line: line)
        }
    }

    // MARK: - Streaming

    private func streamingClient(task: FakeStreamingHTTPTask) -> OpenAICompatibleClient {
        let transport = FakeStreamingHTTPTransport()
        transport.enqueue(task: task)
        return OpenAICompatibleClient(
            configuration: .init(endpoint: Self.endpoint, apiKey: "sk-test"),
            streamingTransport: transport
        )
    }

    private func successfulTask(_ chunks: [Data]) -> FakeStreamingHTTPTask {
        let task = FakeStreamingHTTPTask()
        task.yield(.response(HTTPURLResponse(url: Self.endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!))
        chunks.forEach { task.yield(.data($0)) }
        task.finish()
        return task
    }

    private func assertStreamError(_ expected: ChatServiceError, task: FakeStreamingHTTPTask, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await collect(streamingClient(task: task).stream(request: sampleRequest()))
            XCTFail("expected \(expected)", file: file, line: line)
        } catch let error as ChatServiceError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("unexpected error \(error)", file: file, line: line)
        }
    }

    func testStreamYieldsDeltasUntilDone() async throws {
        let payload = "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"content\":\" world\"}}]}\n\ndata: [DONE]\n\n"
        let pieces = try await collect(streamingClient(task: successfulTask([Data(payload.utf8)])).stream(request: sampleRequest()))
        XCTAssertEqual(pieces, ["Hello", " world"])
    }

    func testStreamEndsImmediatelyOnDoneWithoutEvents() async throws {
        let pieces = try await collect(streamingClient(task: successfulTask([Data("data: [DONE]\n\n".utf8)])).stream(request: sampleRequest()))
        XCTAssertTrue(pieces.isEmpty)
    }

    func testStreamIgnoresEmptyAndNullDeltas() async throws {
        let payload = "data: {\"choices\":[{\"delta\":{\"content\":\"\"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"content\":null}}]}\n\ndata: [DONE]\n\n"
        let pieces = try await collect(streamingClient(task: successfulTask([Data(payload.utf8)])).stream(request: sampleRequest()))
        XCTAssertTrue(pieces.isEmpty)
    }

    func testStreamHandlesIncrementalByteFlushing() async throws {
        let payload = "data: {\"choices\":[{\"delta\":{\"content\":\"你好\"}}]}\n\ndata: [DONE]\n\n"
        let pieces = try await collect(streamingClient(task: successfulTask([Data(payload.utf8)])).stream(request: sampleRequest()))
        XCTAssertEqual(pieces, ["你好"])
    }

    func testUnterminatedStreamFlushesFinalEvent() async throws {
        let payload = "data: {\"choices\":[{\"delta\":{\"content\":\"tail\"}}]}"
        let pieces = try await collect(streamingClient(task: successfulTask([Data(payload.utf8)])).stream(request: sampleRequest()))
        XCTAssertEqual(pieces, ["tail"])
    }

    func testHTTPStatusMapsProviderErrors() async {
        for (status, expected) in [(400, ChatServiceError.invalidRequest(message: "bad body")), (401, .unauthorized(message: "bad body")), (403, .unauthorized(message: "bad body")), (429, .rateLimited(message: "bad body")), (500, .serverError(message: "bad body"))] {
            let task = FakeStreamingHTTPTask()
            task.yield(.response(HTTPURLResponse(url: Self.endpoint, statusCode: status, httpVersion: nil, headerFields: nil)!))
            task.yield(.data(Data(#"{"error":{"message":"bad body"}}"#.utf8)))
            task.finish()
            await assertStreamError(expected, task: task)
        }
    }

    func testMalformedJSONThrowsInvalidResponse() async {
        await assertStreamError(.invalidResponse, task: successfulTask([Data("data: {\"choices\":\n\n".utf8)]))
    }

    func testTransportErrorMapsToNetwork() async {
        let task = FakeStreamingHTTPTask()
        task.finish(throwing: URLError(.notConnectedToInternet))
        await assertStreamError(.network(code: URLError.notConnectedToInternet.rawValue), task: task)
    }

    func testRequestEncodesEachInputMessageExactlyOnce() async throws {
        let task = successfulTask([Data("data: [DONE]\n\n".utf8)])
        let client = streamingClient(task: task)
        let image = ChatContentPart.image(.init(mimeType: "image/png", base64: "aGVsbG8="))
        let request = ChatRequest(model: "gpt-test", messages: [
            ChatInputMessage(role: .system, content: [.text("You are helpful.")]),
            ChatInputMessage(role: .user, content: [.text("Describe this:"), image]),
            ChatInputMessage(role: .assistant, content: [.text("Sure.")]),
        ])
        _ = try await collect(client.stream(request: request))
        let body = try XCTUnwrap(task.request?.httpBody)
        let wire = try JSONDecoder().decode(WireBody.self, from: body)
        XCTAssertEqual(wire.messages.count, 3)
        XCTAssertEqual(wire.messages.map(\.role), [.system, .user, .assistant])
        XCTAssertEqual(wire.messages[1].content, [.text("Describe this:"), image])
    }

    func testRequestCarriesExpectedHeadersAndMethod() async throws {
        let task = successfulTask([Data("data: [DONE]\n\n".utf8)])
        _ = try await collect(streamingClient(task: task).stream(request: sampleRequest()))
        let request = try XCTUnwrap(task.request)
        XCTAssertEqual(request.url, Self.endpoint)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    // MARK: - Cancellation

    func testInjectedTransportYieldsFirstDeltaAndCancelsDeterministically() async throws {
        let transport = FakeStreamingHTTPTransport()
        let client = OpenAICompatibleClient(configuration: .init(endpoint: Self.endpoint, apiKey: "sk-test"), streamingTransport: transport)
        let task = transport.enqueue()
        let (firstDelta, firstDeltaContinuation) = AsyncStream<Void>.makeStream()
        let consumer = Task {
            var pieces: [String] = []
            do {
                for try await piece in client.stream(request: sampleRequest()) {
                    pieces.append(piece)
                    firstDeltaContinuation.yield(())
                }
                try Task.checkCancellation()
                return (error: nil as Error?, pieces: pieces)
            } catch { return (error: error, pieces: pieces) }
        }
        await transport.waitForRequest()
        task.yield(.response(HTTPURLResponse(url: Self.endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!))
        task.yield(.data(Data("data: {\"choices\":[{\"delta\":{\"content\":\"part\"}}]}\n\n".utf8)))
        var iterator = firstDelta.makeAsyncIterator()
        _ = await iterator.next()
        consumer.cancel()
        let result = await consumer.value
        XCTAssertTrue(result.error is CancellationError, "expected CancellationError, got \(String(describing: result.error))")
        XCTAssertEqual(result.pieces, ["part"])
        XCTAssertEqual(task.cancelCount, 1)
    }

    // MARK: - Title generation

    func testGenerateTitleReturnsContent() async throws {
        StubURLProtocol.handler = { _ in
            .init(chunks: [Data(#"{"choices":[{"message":{"role":"assistant","content":"标题"}}]}"#.utf8)])
        }
        let title = try await makeClient().generateTitle(request: titleRequest())
        XCTAssertEqual(title, "标题")
    }

    func testGenerateTitleMapsRateLimit() async {
        StubURLProtocol.handler = { _ in
            .init(statusCode: 429, chunks: [Data(#"{"error":{"message":"nope"}}"#.utf8)])
        }
        do {
            _ = try await makeClient().generateTitle(request: titleRequest())
            XCTFail("expected error")
        } catch let error as ChatServiceError {
            XCTAssertEqual(error, .rateLimited(message: "nope"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testGenerateTitleRejectsEmptyContent() async {
        StubURLProtocol.handler = { _ in
            .init(chunks: [Data(#"{"choices":[{"message":{"content":""}}]}"#.utf8)])
        }
        do {
            _ = try await makeClient().generateTitle(request: titleRequest())
            XCTFail("expected error")
        } catch let error as ChatServiceError {
            XCTAssertEqual(error, .invalidResponse)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testGenerateTitleSendsNonStreamingBody() async throws {
        var capturedBody: Data?
        StubURLProtocol.handler = { request in
            capturedBody = request.httpBody
            return .init(chunks: [Data(#"{"choices":[{"message":{"content":"x"}}]}"#.utf8)])
        }
        _ = try await makeClient().generateTitle(request: titleRequest())

        let body = try XCTUnwrap(capturedBody)
        let wire = try JSONDecoder().decode(WireBody.self, from: body)
        XCTAssertEqual(wire.stream, false)
        XCTAssertEqual(wire.model, "gpt-test")
        XCTAssertEqual(wire.messages.count, 1)
        XCTAssertEqual(wire.messages[0].role, .user)
    }
}

private final class FakeStreamingHTTPTransport: StreamingHTTPTransport {
    private let requestStarted: AsyncStream<Void>
    private let requestStartedContinuation: AsyncStream<Void>.Continuation
    private var queuedTasks: [FakeStreamingHTTPTask] = []

    init() {
        (requestStarted, requestStartedContinuation) = AsyncStream.makeStream()
    }

    func enqueue(task: FakeStreamingHTTPTask) {
        queuedTasks.append(task)
    }

    func enqueue() -> FakeStreamingHTTPTask {
        let task = FakeStreamingHTTPTask()
        enqueue(task: task)
        return task
    }

    func start(request: URLRequest) -> any StreamingHTTPTask {
        let task = queuedTasks.removeFirst()
        task.request = request
        requestStartedContinuation.yield(())
        return task
    }

    func waitForRequest() async {
        var iterator = requestStarted.makeAsyncIterator()
        _ = await iterator.next()
    }
}

private final class FakeStreamingHTTPTask: StreamingHTTPTask {
    let events: AsyncThrowingStream<StreamingHTTPEvent, Error>
    private let continuation: AsyncThrowingStream<StreamingHTTPEvent, Error>.Continuation
    private(set) var cancelCount = 0
    var request: URLRequest?

    init() {
        (events, continuation) = AsyncThrowingStream.makeStream()
    }

    func yield(_ event: StreamingHTTPEvent) {
        continuation.yield(event)
    }

    func finish(throwing error: Error? = nil) {
        if let error {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }
    }

    func cancel() {
        cancelCount += 1
        continuation.finish(throwing: CancellationError())
    }
}

/// Mirrors the wire format of the Chat Completions body so tests can assert the
/// exact bytes the client produced.
private struct WireBody: Decodable {
    var model: String
    var messages: [ChatInputMessage]
    var stream: Bool
}
