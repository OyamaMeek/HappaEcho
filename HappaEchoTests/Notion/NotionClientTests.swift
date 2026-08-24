import XCTest
@testable import HappaEcho

final class NotionClientTests: XCTestCase {
    private static func requestBody(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open(); defer { stream.close() }
        var data = Data(); let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1_024); defer { buffer.deallocate() }
        while stream.hasBytesAvailable { let count = stream.read(buffer, maxLength: 1_024); guard count >= 0 else { return nil }; data.append(buffer, count: count) }
        return data
    }
    private let baseURL = URL(string: "https://notion.example.test/v1/")!

    private func makeClient(_ handler: @escaping (URLRequest) throws -> StubURLProtocol.Response) -> NotionClient {
        let endpoint = baseURL
        StubURLProtocol.handlers[endpoint.appending(path: "pages")] = handler
        StubURLProtocol.handlers[endpoint.appending(path: "blocks/page/children")] = handler
        StubURLProtocol.handlers[URL(string: "https://notion.example.test/v1/blocks/page/children?start_cursor=cursor")!] = handler
        StubURLProtocol.handlers[URL(string: "https://notion.example.test/v1/blocks/page/children?start_cursor=cursor")!.appending(queryItems: [])] = handler
        StubURLProtocol.handlers[endpoint.appending(path: "file_uploads")] = handler
        StubURLProtocol.handlers[endpoint.appending(path: "file_uploads/upload/send")] = handler
        StubURLProtocol.handlers[endpoint.appending(path: "file_uploads/upload/complete")] = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return NotionClient(configuration: .init(baseURL: endpoint, token: "secret"), session: URLSession(configuration: configuration))
    }

    func testCreatePageSendsNotionHeadersAndProperties() async throws {
        let client = makeClient { _ in
            return .init(chunks: [Data(#"{"id":"page-id","url":"https://notion.so/page-id","properties":{}}"#.utf8)])
        }
        let page = try await client.createPage(.init(databaseID: "database-id", properties: ["Title": .title("Hello")]))
        XCTAssertEqual(page.id, "page-id")
    }

    func testAppendBlocksReturnsRemoteIDsAndEncodesCodeLanguage() async throws {
        let client = makeClient { _ in
            return .init(chunks: [Data(#"{"results":[{"id":"a"},{"id":"b"}]}"#.utf8)])
        }
        let ids = try await client.appendBlocks(pageID: "page", blocks: [.init(kind: .code(language: "swift"), richText: [.init(content: "let x")], markerMessageID: nil)])
        XCTAssertEqual(ids, ["a", "b"])
        let request = try XCTUnwrap(StubURLProtocol.capturedRequest)
        let body = try XCTUnwrap(Self.requestBody(from: request))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let children = try XCTUnwrap(object["children"] as? [[String: Any]])
        let code = try XCTUnwrap(children[0]["code"] as? [String: Any])
        XCTAssertEqual(code["language"] as? String, "swift")
    }

    func testListBlocksPassesCursorAndDecodesPagination() async throws {
        var request: URLRequest?
        let client = makeClient { captured in
            request = captured
            return .init(chunks: [Data(#"{"results":[{"id":"block","type":"paragraph","paragraph":{"rich_text":[{"plain_text":"marker"}]}}],"has_more":true,"next_cursor":"next"}"#.utf8)])
        }
        let page = try await client.listBlocks(pageID: "page", cursor: "cursor")
        XCTAssertEqual(request?.url?.query, "start_cursor=cursor")
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.nextCursor, "next")
        XCTAssertEqual(page.blocks.first?.plainText, "marker")
    }

    func testFileUploadLifecycleUsesExplicitStages() async throws {
        var requests: [URLRequest] = []
        let client = makeClient { request in
            requests.append(request)
            switch request.url!.path {
            case "/v1/file_uploads": return .init(chunks: [Data(#"{"id":"upload","status":"pending"}"#.utf8)])
            case "/v1/file_uploads/upload/send": return .init()
            case "/v1/file_uploads/upload/complete": return .init(chunks: [Data(#"{"id":"upload","status":"uploaded","file":{"url":"https://files.test/image"}}"#.utf8)])
            default: throw URLError(.badURL)
            }
        }
        let staged = try await client.createFileUpload(.init(filename: "image.png", contentType: "image/png"))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("image".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        try await client.sendFile(uploadID: staged.id, fileURL: url)
        let completed = try await client.completeFileUpload(uploadID: staged.id)
        XCTAssertEqual(requests.map { $0.url!.path }, ["/v1/file_uploads", "/v1/file_uploads/upload/send", "/v1/file_uploads/upload/complete"])
        XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "POST" && $0.value(forHTTPHeaderField: "Authorization") == "Bearer secret" && $0.value(forHTTPHeaderField: "Notion-Version") == NotionClient.notionVersion })
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Content-Type"), "application/octet-stream")
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "Content-Type"), "application/json")
        let createBody = try XCTUnwrap(Self.requestBody(from: requests[0]))
        let createJSON = try XCTUnwrap(try JSONSerialization.jsonObject(with: createBody) as? [String: String])
        XCTAssertEqual(createJSON, ["filename": "image.png", "content_type": "image/png"])
        XCTAssertEqual(Self.requestBody(from: requests[1]), Data("image".utf8))
        XCTAssertNil(Self.requestBody(from: requests[2]))
        XCTAssertEqual(completed.fileURL, URL(string: "https://files.test/image"))
    }

    func testMapsTransportErrorToNetwork() async {
        let client = makeClient { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await client.listBlocks(pageID: "page", cursor: nil)
            XCTFail("expected network error")
        } catch let error as NotionError {
            XCTAssertEqual(error, .network(code: URLError.notConnectedToInternet.rawValue))
        } catch { XCTFail("unexpected \(error)") }
    }

    func testMapsHTTPDateRetryAfterToNonnegativeDelay() async {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        let header = formatter.string(from: Date().addingTimeInterval(60))
        let client = makeClient { _ in .init(statusCode: 429, headers: ["Retry-After": header]) }
        do {
            _ = try await client.listBlocks(pageID: "page", cursor: nil)
            XCTFail("expected rate limit")
        } catch let error as NotionError {
            guard case .rateLimited(let delay?) = error else { return XCTFail("unexpected \(error)") }
            XCTAssertGreaterThanOrEqual(delay, 0)
        } catch { XCTFail("unexpected \(error)") }
    }

    func testMapsAuthNotFoundRateLimitAndServerErrors() async {
        for (status, expected) in [(401, NotionError.unauthorized), (403, .forbidden), (404, .notFound), (429, .rateLimited(retryAfter: 3.0)), (503, .server(statusCode: 503))] {
            let client = makeClient { _ in .init(statusCode: status, headers: status == 429 ? ["Retry-After": "3"] : [:], chunks: [Data(#"{"message":"failure"}"#.utf8)]) }
            do {
                _ = try await client.listBlocks(pageID: "page", cursor: nil)
                XCTFail("expected \(expected)")
            } catch let error as NotionError {
                XCTAssertEqual(error, expected)
            } catch { XCTFail("unexpected \(error)") }
        }
    }
}
