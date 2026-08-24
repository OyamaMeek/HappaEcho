import XCTest
@testable import HappaEcho

final class MultimodalRequestBodyTests: XCTestCase {
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLXLwAAAABJRU5ErkJggg==")!
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testWritesDataURLWithCorrectMIMEAndExactContentLength() async throws {
        let imageURL = root.appending(path: "fixture.png")
        try png.write(to: imageURL)
        let attachment = attachment(at: imageURL)
        let body = MultimodalRequestBody(request: ChatRequest(model: "vision", messages: [
            ChatInputMessage(role: .user, content: [.text("describe")])
        ]), attachmentsByMessage: [[attachment]], attachmentRootURL: root)

        let prepared = try await body.prepareTemporaryFile()
        defer { prepared.cleanup() }
        let data = try Data(contentsOf: prepared.fileURL)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let messages = json["messages"] as! [[String: Any]]
        let content = messages[0]["content"] as! [[String: Any]]
        let imageURLString = ((content[1]["image_url"] as! [String: String])["url"])!

        XCTAssertEqual(imageURLString, "data:image/png;base64,\(png.base64EncodedString())")
        XCTAssertEqual(prepared.contentLength, Int64(data.count))
        XCTAssertEqual(prepared.contentType, "application/json")
        XCTAssertNotNil(prepared.openStream())
    }

    func testConfiguredImageLimitFailsBeforeWritingRequest() async throws {
        let imageURL = root.appending(path: "fixture.png")
        try png.write(to: imageURL)
        let body = MultimodalRequestBody(request: ChatRequest(model: "vision", messages: []), attachmentsByMessage: [[attachment(at: imageURL)]], limits: .init(maxImageBytes: png.count - 1), attachmentRootURL: root)

        await XCTAssertThrowsErrorAsync(try await body.prepareTemporaryFile()) { error in
            XCTAssertEqual(error as? MultimodalRequestBodyError, .imageTooLarge(index: 0))
        }
    }

    func testConfiguredTotalLimitFailsBeforeWritingRequest() async throws {
        let imageURL = root.appending(path: "fixture.png")
        try png.write(to: imageURL)
        let body = MultimodalRequestBody(request: ChatRequest(model: "vision", messages: []), attachmentsByMessage: [[attachment(at: imageURL)]], limits: .init(maxRequestBodyBytes: 1), attachmentRootURL: root)

        await XCTAssertThrowsErrorAsync(try await body.prepareTemporaryFile()) { error in
            XCTAssertEqual(error as? MultimodalRequestBodyError, .requestTooLarge)
        }
    }

    private func attachment(at url: URL) -> MessageAttachment {
        MessageAttachment(userOrder: 0, originalFileName: "fixture.png", utType: "public.png", mimeType: "image/png", pixelWidth: 1, pixelHeight: 1, fileSize: png.count, relativePath: "fixture.png")
    }
}

private func XCTAssertThrowsErrorAsync<T>(_ expression: @autoclosure () async throws -> T, _ handler: (Error) -> Void) async {
    do { _ = try await expression(); XCTFail("Expected error") }
    catch { handler(error) }
}
