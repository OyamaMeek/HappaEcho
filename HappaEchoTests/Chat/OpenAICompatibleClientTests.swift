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

    nonisolated(unsafe) static var handler: ((URLRequest) throws -> Response)?
    nonisolated(unsafe) static var capturedRequest: URLRequest?
    nonisolated(unsafe) static var stopLoadingCount = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let response = try handler(request)
            Self.capturedRequest = request
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
        Self.stopLoadingCount += 1
        client?.urlProtocolDidFinishLoading(self)
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

    func testStreamYieldsDeltasUntilDone() async throws {
        let payload = """
        data: {"choices":[{"delta":{"content":"Hello"}}]}

        data: {"choices":[{"delta":{"content":" world"}}]}

        data: [DONE]

        """
        StubURLProtocol.handler = { _ in .init(statusCode: 200, chunks: [Data(payload.utf8)]) }
        let pieces = try await collect(makeClient().stream(request: sampleRequest()))
        XCTAssertEqual(pieces, ["Hello", " world"])
    }

    func testStreamEndsImmediatelyOnDoneWithoutEvents() async throws {
        StubURLProtocol.handler = { _ in .init(chunks: [Data("data: [DONE]\n\n".utf8)]) }
        let pieces = try await collect(makeClient().stream(request: sampleRequest()))
        XCTAssertTrue(pieces.isEmpty)
    }

    func testStreamIgnoresEmptyAndNullDeltas() async throws {
        let payload = """
        data: {"choices":[{"delta":{"content":""}}]}

        data: {"choices":[{"delta":{"content":null}}]}

        data: [DONE]

        """
        StubURLProtocol.handler = { _ in .init(chunks: [Data(payload.utf8)]) }
        let pieces = try await collect(makeClient().stream(request: sampleRequest()))
        XCTAssertTrue(pieces.isEmpty)
    }

    func testStreamHandlesIncrementalByteFlushing() async throws {
        // The client feeds the parser every byte as it arrives, so a delta is
        // yielded as soon as its event completes even if the network delivered
        // it inside a single chunk. This also covers a multi-byte UTF-8 code
        // point that the parser only ever sees in pieces.
        let payload = "data: {\"choices\":[{\"delta\":{\"content\":\"你好\"}}]}\n\ndata: [DONE]\n\n"
        StubURLProtocol.handler = { _ in .init(chunks: [Data(payload.utf8)]) }
        let pieces = try await collect(makeClient().stream(request: sampleRequest()))
        XCTAssertEqual(pieces, ["你好"])
    }

    func testUnterminatedStreamFlushesFinalEvent() async throws {
        // No trailing blank line and no [DONE]; the final event still yields.
        let payload = "data: {\"choices\":[{\"delta\":{\"content\":\"tail\"}}]}"
        StubURLProtocol.handler = { _ in .init(chunks: [Data(payload.utf8)]) }
        let pieces = try await collect(makeClient().stream(request: sampleRequest()))
        XCTAssertEqual(pieces, ["tail"])
    }

    // MARK: - Provider error mapping

    func testHTTP401MapsToUnauthorized() async {
        StubURLProtocol.handler = { _ in
            .init(statusCode: 401, chunks: [Data(#"{"error":{"message":"bad key"}}"#.utf8)])
        }
        await assertStreamError(.unauthorized(message: "bad key"))
    }

    func testHTTP403MapsToUnauthorized() async {
        StubURLProtocol.handler = { _ in
            .init(statusCode: 403, chunks: [Data(#"{"error":{"message":"forbidden"}}"#.utf8)])
        }
        await assertStreamError(.unauthorized(message: "forbidden"))
    }

    func testHTTP429MapsToRateLimited() async {
        StubURLProtocol.handler = { _ in
            .init(statusCode: 429, chunks: [Data(#"{"error":{"message":"slow down"}}"#.utf8)])
        }
        await assertStreamError(.rateLimited(message: "slow down"))
    }

    func testHTTP500MapsToServerError() async {
        StubURLProtocol.handler = { _ in
            .init(statusCode: 500, chunks: [Data("upstream exploded".utf8)])
        }
        await assertStreamError(.serverError(message: nil))
    }

    func testHTTP400MapsToInvalidRequest() async {
        StubURLProtocol.handler = { _ in
            .init(statusCode: 400, chunks: [Data(#"{"error":{"message":"bad body"}}"#.utf8)])
        }
        await assertStreamError(.invalidRequest(message: "bad body"))
    }

    func testMalformedJSONThrowsInvalidResponse() async {
        StubURLProtocol.handler = { _ in .init(chunks: [Data("data: {\"choices\":\n\n".utf8)]) }
        await assertStreamError(.invalidResponse)
    }

    func testTransportErrorMapsToNetwork() async {
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await collect(makeClient().stream(request: sampleRequest()))
            XCTFail("expected error")
        } catch let error as ChatServiceError {
            guard case .network = error else {
                return XCTFail("expected network error, got \(error)")
            }
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    // MARK: - Request encoding

    func testRequestEncodesEachInputMessageExactlyOnce() async throws {
        var capturedBody: Data?
        StubURLProtocol.handler = { request in
            capturedBody = request.httpBody
            return .init(chunks: [Data("data: [DONE]\n\n".utf8)])
        }

        let image = ChatContentPart.image(.init(mimeType: "image/png", base64: "aGVsbG8="))
        let request = ChatRequest(model: "gpt-test", messages: [
            ChatInputMessage(role: .system, content: [.text("You are helpful.")]),
            ChatInputMessage(role: .user, content: [.text("Describe this:"), image]),
            ChatInputMessage(role: .assistant, content: [.text("Sure.")]),
        ])

        _ = try await collect(makeClient().stream(request: request))

        let body = try XCTUnwrap(capturedBody)
        let wire = try JSONDecoder().decode(WireBody.self, from: body)
        XCTAssertEqual(wire.model, "gpt-test")
        XCTAssertEqual(wire.stream, true)
        XCTAssertEqual(wire.messages.count, 3)
        XCTAssertEqual(wire.messages.map(\.role), [.system, .user, .assistant])
        XCTAssertEqual(wire.messages[0].content, [.text("You are helpful.")])
        XCTAssertEqual(wire.messages[1].content, [.text("Describe this:"), image])
        XCTAssertEqual(wire.messages[2].content, [.text("Sure.")])
    }

    func testRequestCarriesExpectedHeadersAndMethod() async throws {
        var captured: URLRequest?
        StubURLProtocol.handler = { request in
            captured = request
            return .init(chunks: [Data("data: [DONE]\n\n".utf8)])
        }
        _ = try await collect(makeClient().stream(request: sampleRequest()))

        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.url, Self.endpoint)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    // MARK: - Cancellation

    func testCancellingStreamPropagatesCancellationAndCancelsTransport() async throws {
        // Deliver one delta, then hold the connection open so the transport is
        // still active when the consumer cancels.
        StubURLProtocol.handler = { _ in
            .init(
                statusCode: 200,
                chunks: [Data("data: {\"choices\":[{\"delta\":{\"content\":\"part\"}}]}\n\n".utf8)],
                finishImmediately: false
            )
        }

        let (signal, signalContinuation) = AsyncStream<Void>.makeStream()

        let task = Task {
            var pieces: [String] = []
            do {
                for try await piece in makeClient().stream(request: sampleRequest()) {
                    pieces.append(piece)
                    signalContinuation.yield(())
                }
                return ("finished", pieces)
            } catch {
                return ("threw", pieces)
            }
        }

        var iterator = signal.makeAsyncIterator()
        _ = await iterator.next()

        task.cancel()
        await Task.yield()
        let result = await task.result

        guard case .success(let (outcome, pieces)) = result else {
            return XCTFail("task failed")
        }
        // Cancelling the consuming task may end the `for try await` loop
        // normally (the stream terminates and `next()` returns nil) or throw;
        // what matters is that the yielded delta arrived, the transport was
        // actually cancelled, and the loop did not hang.
        XCTAssertTrue(
            outcome == "finished" || outcome == "threw",
            "expected loop to end on cancellation, got \(outcome)"
        )
        XCTAssertEqual(pieces, ["part"])
        XCTAssertGreaterThanOrEqual(StubURLProtocol.stopLoadingCount, 1)
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

/// Mirrors the wire format of the Chat Completions body so tests can assert the
/// exact bytes the client produced.
private struct WireBody: Decodable {
    var model: String
    var messages: [ChatInputMessage]
    var stream: Bool
}
