import Foundation

/// Sends OpenAI-compatible Chat Completions requests.
///
/// Implementations must yield assistant text as it streams, terminate on
/// `[DONE]`, map provider errors to `ChatServiceError`, and never swallow
/// cancellation.
protocol ChatCompletionService {
    /// Streams assistant deltas for the request. The stream finishes normally
    /// on `[DONE]` or end of response and throws `ChatServiceError` (or
    /// `CancellationError` when the caller cancels).
    func stream(request: ChatRequest) -> AsyncThrowingStream<String, Error>
    /// Requests a short non-streaming completion and returns its text.
    func generateTitle(request: TitleRequest) async throws -> String
}

/// URLSession-backed `ChatCompletionService` speaking the OpenAI Chat
/// Completions SSE protocol.
final class OpenAICompatibleClient: ChatCompletionService {
    struct Configuration: Sendable {
        var endpoint: URL
        var apiKey: String
        var timeoutInterval: TimeInterval = 60
    }

    private let configuration: Configuration
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder: JSONDecoder

    init(configuration: Configuration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    // MARK: - ChatCompletionService

    func stream(request: ChatRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try makeURLRequest(model: request.model, messages: request.messages, stream: true)
                    let transport = StreamingURLSessionTask(session: session, request: urlRequest)
                    var response: HTTPURLResponse?
                    var body = Data()
                    var parser = ServerSentEventParser()
                    try await withTaskCancellationHandler {
                        for try await event in transport.events {
                            try Task.checkCancellation()
                            switch event {
                            case .response(let value):
                                guard let http = value as? HTTPURLResponse else { throw HTTPError.invalidResponse }
                                response = http
                            case .data(let data):
                                guard let http = response else { throw HTTPError.invalidResponse }
                                if !(200..<300).contains(http.statusCode) {
                                    body.append(data)
                                } else {
                                    for byte in data {
                                        if try process(parser.append(byte), continuation: continuation) {
                                            transport.cancel()
                                            return
                                        }
                                    }
                                }
                            }
                        }
                    } onCancel: {
                        transport.cancel()
                    }
                    try Task.checkCancellation()
                    guard let http = response else { throw HTTPError.invalidResponse }
                    guard (200..<300).contains(http.statusCode) else {
                        throw HTTPError.statusCode(http.statusCode, message: Self.parseProviderMessage(body))
                    }
                    if try process(parser.finish(), continuation: continuation) { return }
                    continuation.finish()
                } catch {
                    handleFailure(error, continuation: continuation)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func generateTitle(request: TitleRequest) async throws -> String {
        do {
            let urlRequest = try makeURLRequest(model: request.model, messages: request.messages, stream: false)
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                throw HTTPError.invalidResponse
            }
            guard (200..<300).contains(http.statusCode) else {
                throw HTTPError.statusCode(http.statusCode, message: Self.parseProviderMessage(data))
            }
            let completion = try decoder.decode(ChatCompletion.self, from: data)
            guard let content = completion.choices.first?.message.content, !content.isEmpty else {
                throw ChatServiceError.invalidResponse
            }
            return content
        } catch {
            if Self.isCancellation(error) {
                throw CancellationError()
            }
            if let httpError = error as? HTTPError {
                switch httpError {
                case .invalidResponse:
                    throw ChatServiceError.invalidResponse
                case .statusCode(let statusCode, let message):
                    throw Self.mapError(statusCode: statusCode, message: message)
                }
            }
            if error is DecodingError {
                throw ChatServiceError.invalidResponse
            }
            throw Self.mapTransport(error)
        }
    }

    // MARK: - Request construction

    private func makeURLRequest(model: String, messages: [ChatInputMessage], stream: Bool) throws -> URLRequest {
        guard !configuration.apiKey.isEmpty else {
            throw ChatServiceError.invalidConfiguration
        }
        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = configuration.timeoutInterval
        request.httpBody = try encoder.encode(ChatCompletionBody(model: model, messages: messages, stream: stream))
        return request
    }

    // MARK: - Delta extraction

    /// Yields deltas for a batch of events. Returns `true` when the stream
    /// should terminate (`[DONE]` seen and the continuation finished).
    private func process(
        _ events: [ServerSentEvent],
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) throws -> Bool {
        for event in events {
            try Task.checkCancellation()
            if event.data == "[DONE]" {
                continuation.finish()
                return true
            }
            if let delta = try extractDelta(from: event.data) {
                continuation.yield(delta)
            }
        }
        return false
    }

    private func extractDelta(from data: String) throws -> String? {
        guard !data.isEmpty else { return nil }
        let chunk = try decoder.decode(ChatChunk.self, from: Data(data.utf8))
        guard let content = chunk.choices.first?.delta.content, !content.isEmpty else { return nil }
        return content
    }

    // MARK: - Failure mapping

    private func handleFailure(_ error: Error, continuation: AsyncThrowingStream<String, Error>.Continuation) {
        if Self.isCancellation(error) {
            // Re-throw the same error async/await uses; never swallow it.
            continuation.finish(throwing: CancellationError())
            return
        }
        if let httpError = error as? HTTPError {
            switch httpError {
            case .invalidResponse:
                continuation.finish(throwing: ChatServiceError.invalidResponse)
            case .statusCode(let statusCode, let message):
                continuation.finish(throwing: Self.mapError(statusCode: statusCode, message: message))
            }
            return
        }
        if error is DecodingError {
            continuation.finish(throwing: ChatServiceError.invalidResponse)
            return
        }
        continuation.finish(throwing: Self.mapTransport(error))
    }

    static func mapError(statusCode: Int, message: String?) -> ChatServiceError {
        switch statusCode {
        case 400:
            return .invalidRequest(message: message)
        case 401, 403:
            return .unauthorized(message: message)
        case 429:
            return .rateLimited(message: message)
        case 500..<600:
            return .serverError(message: message)
        default:
            return .unexpectedStatusCode(statusCode: statusCode, message: message)
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        return false
    }

    private static func mapTransport(_ error: Error) -> ChatServiceError {
        if let urlError = error as? URLError {
            return .network(code: urlError.code.rawValue)
        }
        return .network(code: nil)
    }

    private static func readProviderMessage(from bytes: URLSession.AsyncBytes) async throws -> String? {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
        }
        return parseProviderMessage(data)
    }

    private static func parseProviderMessage(_ data: Data) -> String? {
        struct ErrorEnvelope: Decodable {
            struct ErrorPayload: Decodable {
                var message: String?
            }
            var error: ErrorPayload?
        }
        guard let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) else { return nil }
        return envelope.error?.message
    }
}

private final class StreamingURLSessionTask: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    enum Event {
        case response(URLResponse)
        case data(Data)
    }

    let events: AsyncThrowingStream<Event, Error>
    private var task: URLSessionDataTask!
    private var continuation: AsyncThrowingStream<Event, Error>.Continuation?
    private var session: URLSession?

    init(session: URLSession, request: URLRequest) {
        var continuation: AsyncThrowingStream<Event, Error>.Continuation?
        events = AsyncThrowingStream { continuation = $0 }
        self.continuation = continuation
        super.init()
        let configuration = session.configuration
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        let delegateSession = URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
        self.session = delegateSession
        task = delegateSession.dataTask(with: request)
        task.resume()
    }

    func cancel() {
        task.cancel()
        session?.invalidateAndCancel()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        continuation?.yield(.response(response))
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        continuation?.yield(.data(data))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            continuation?.finish(throwing: error)
        } else {
            continuation?.finish()
        }
        continuation = nil
        self.session = nil
    }
}


private struct ChatCompletionBody: Encodable {
    var model: String
    var messages: [ChatInputMessage]
    var stream: Bool
}

/// Streaming chunk: `{"choices":[{"delta":{"content":"…"}}]}`.
private struct ChatChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            var content: String?
        }
        var delta: Delta
    }
    var choices: [Choice]
}

/// Non-streaming completion: `{"choices":[{"message":{"content":"…"}}]}`.
private struct ChatCompletion: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            var content: String?
        }
        var message: Message
    }
    var choices: [Choice]
}
