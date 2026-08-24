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

    func testConfiguredTotalLimitUsesFinalJSONLengthAndCreatesNoTemporaryFile() async throws {
        let imageURL = root.appending(path: "fixture.png")
        try png.write(to: imageURL)
        let request = ChatRequest(model: "vision-\"日本語", messages: [
            ChatInputMessage(role: .user, content: [.text("quote \" newline\nemoji 😀")])
        ])
        let attachment = MessageAttachment(userOrder: 0, originalFileName: "fixture.png", utType: "public.png", mimeType: "image/png", pixelWidth: 1, pixelHeight: 1, fileSize: png.count, relativePath: "fixture.png")
        let unconstrained = MultimodalRequestBody(request: request, attachmentsByMessage: [[attachment]], attachmentRootURL: root, temporaryDirectory: root)
        let prepared = try await unconstrained.prepareTemporaryFile()
        let finalSize = prepared.contentLength
        prepared.cleanup()
        XCTAssertGreaterThan(finalSize, Int64(png.base64EncodedString().utf8.count))

        let constrained = MultimodalRequestBody(request: request, attachmentsByMessage: [[attachment]], limits: .init(maxRequestBodyBytes: Int(finalSize - 1)), attachmentRootURL: root, temporaryDirectory: root)
        await XCTAssertThrowsErrorAsync(try await constrained.prepareTemporaryFile()) { error in
            XCTAssertEqual(error as? MultimodalRequestBodyError, .requestTooLarge)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("HappaEcho-request-") }.count, 0)
    }

    func testMultipleAttachmentsAreSerializedInStableUserOrder() async throws {
        let first = root.appending(path: "first.png")
        let second = root.appending(path: "second.png")
        let firstData = png
        let secondData = Data(png.dropFirst())
        try firstData.write(to: first)
        try secondData.write(to: second)
        let later = MessageAttachment(userOrder: 9, originalFileName: "second.png", utType: "public.png", mimeType: "image/png", pixelWidth: 1, pixelHeight: 1, fileSize: secondData.count, relativePath: "second.png")
        let earlier = MessageAttachment(userOrder: 2, originalFileName: "first.png", utType: "public.png", mimeType: "image/png", pixelWidth: 1, pixelHeight: 1, fileSize: firstData.count, relativePath: "first.png")
        let body = MultimodalRequestBody(request: ChatRequest(model: "vision", messages: [.init(role: .user, content: [])]), attachmentsByMessage: [[later, earlier]], attachmentRootURL: root)
        let prepared = try await body.prepareTemporaryFile()
        defer { prepared.cleanup() }
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: prepared.fileURL)) as! [String: Any]
        let content = ((object["messages"] as! [[String: Any]])[0]["content"] as! [[String: Any]])
        XCTAssertEqual(((content[0]["image_url"] as! [String: String])["url"])!, "data:image/png;base64,\(firstData.base64EncodedString())")
        XCTAssertEqual(((content[1]["image_url"] as! [String: String])["url"])!, "data:image/png;base64,\(secondData.base64EncodedString())")
    }


    private func attachment(at url: URL) -> MessageAttachment {
        MessageAttachment(userOrder: 0, originalFileName: "fixture.png", utType: "public.png", mimeType: "image/png", pixelWidth: 1, pixelHeight: 1, fileSize: png.count, relativePath: "fixture.png")
    }
}

private func XCTAssertThrowsErrorAsync<T>(_ expression: @autoclosure () async throws -> T, _ handler: (Error) -> Void) async {
    do { _ = try await expression(); XCTFail("Expected error") }
    catch { handler(error) }
}
