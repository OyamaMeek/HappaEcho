import Foundation

/// A task that emits an HTTP response followed by body data for one request.
enum StreamingHTTPEvent {
    case response(URLResponse)
    case data(Data)
}

protocol StreamingHTTPTask: AnyObject {
    var events: AsyncThrowingStream<StreamingHTTPEvent, Error> { get }
    func cancel()
}

protocol StreamingHTTPTransport: AnyObject {
    /// `bodyFileURL` is transport metadata, never emitted as an HTTP header.
    func start(request: URLRequest, bodyFileURL: URL?) -> any StreamingHTTPTask
}

extension StreamingHTTPTransport {
    func start(request: URLRequest) -> any StreamingHTTPTask { start(request: request, bodyFileURL: nil) }
}

final class FileBodyStreamProvider: BodyStreamProviding, @unchecked Sendable {
    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func makeBodyStream() -> InputStream? {
        InputStream(url: fileURL)
    }
}

protocol BodyStreamProviding: AnyObject {
    func makeBodyStream() -> InputStream?
}

final class URLSessionStreamingHTTPTransport: StreamingHTTPTransport {
    private let session: URLSession

    init(session: URLSession) {
        self.session = session
    }

    func start(request: URLRequest, bodyFileURL: URL? = nil) -> any StreamingHTTPTask {
        URLSessionStreamingHTTPTask(session: session, request: request, bodyFileURL: bodyFileURL)
    }
}

private final class URLSessionStreamingHTTPTask: NSObject, StreamingHTTPTask, URLSessionDataDelegate, @unchecked Sendable {
    let events: AsyncThrowingStream<StreamingHTTPEvent, Error>
    private let stateLock = NSLock()
    private var continuation: AsyncThrowingStream<StreamingHTTPEvent, Error>.Continuation?
    private var task: URLSessionDataTask!
    private var bodyStreamProvider: (any BodyStreamProviding)?
    private var delegateSession: URLSession?
    private var finished = false

    init(session: URLSession, request: URLRequest, bodyFileURL: URL?) {
        var capturedContinuation: AsyncThrowingStream<StreamingHTTPEvent, Error>.Continuation?
        events = AsyncThrowingStream { capturedContinuation = $0 }
        continuation = capturedContinuation
        super.init()

        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        let delegateSession = URLSession(configuration: session.configuration, delegate: self, delegateQueue: delegateQueue)
        self.delegateSession = delegateSession
        bodyStreamProvider = bodyFileURL.map(FileBodyStreamProvider.init(fileURL:))
        task = delegateSession.dataTask(with: request)
        task.resume()
    }

    func cancel() {
        let session = finish(throwing: CancellationError())
        task.cancel()
        session?.invalidateAndCancel()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, needNewBodyStream completionHandler: @escaping (InputStream?) -> Void) {
        completionHandler(bodyStreamProvider?.makeBodyStream())
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        yield(.response(response))
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        yield(.data(data))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        _ = finish(throwing: error)
    }

    private func yield(_ event: StreamingHTTPEvent) {
        stateLock.lock()
        let continuation = finished ? nil : continuation
        stateLock.unlock()
        continuation?.yield(event)
    }

    @discardableResult
    private func finish(throwing error: Error? = nil) -> URLSession? {
        stateLock.lock()
        guard !finished else {
            stateLock.unlock()
            return nil
        }
        finished = true
        let continuation = continuation
        self.continuation = nil
        let session = delegateSession
        delegateSession = nil
        stateLock.unlock()

        if let error {
            continuation?.finish(throwing: error)
        } else {
            continuation?.finish()
        }
        return session
    }
}
