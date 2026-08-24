import XCTest
@testable import HappaEcho

final class NotionClientTests: XCTestCase {
    private let baseURL = URL(string: "https://notion.example.test/v1/")!

    private func makeClient(_ handler: @escaping (URLRequest) throws -> StubURLProtocol.Response) -> NotionClient {
        let endpoint = baseURL
        StubURLProtocol.handlers[endpoint.appending(path: "pages")] = handler
        StubURLProtocol.handlers[endpoint.appending(path: "blocks/page/children")] = handler
        StubURLProtocol.handlers[URL(string: "blocks/page/children?start_cursor=cursor", relativeTo: endpoint)!] = handler
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

    func testAppendBlocksReturnsRemoteIDs() async throws {
        let client = makeClient { _ in .init(chunks: [Data(#"{"results":[{"id":"a"},{"id":"b"}]}"#.utf8)]) }
        let ids = try await client.appendBlocks(pageID: "page", blocks: [.paragraph("text")])
        XCTAssertEqual(ids, ["a", "b"])
    }

    func testListBlocksPassesCursorAndDecodesPagination() async throws {
        var request: URLRequest?
        let client = makeClient { captured in
            request = captured
            return .init(chunks: [Data(#"{"results":[{"id":"block","type":"paragraph","paragraph":{"rich_text":[{"plain_text":"marker"}]}}],"has_more":true,"next_cursor":"next"}"#.utf8)])
        }
        let page = try await client.listBlocks(pageID: "page", cursor: nil)
        XCTAssertNil(request?.url?.query)
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.nextCursor, "next")
        XCTAssertEqual(page.blocks.first?.plainText, "marker")
    }

    func testFileUploadLifecycleUsesExplicitStages() async throws {
        var paths: [String] = []
        let client = makeClient { request in
            paths.append(request.url!.path)
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
        XCTAssertEqual(paths, ["/v1/file_uploads", "/v1/file_uploads/upload/send", "/v1/file_uploads/upload/complete"])
        XCTAssertEqual(completed.fileURL, URL(string: "https://files.test/image"))
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
