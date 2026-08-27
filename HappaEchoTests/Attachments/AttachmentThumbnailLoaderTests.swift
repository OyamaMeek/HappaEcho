import XCTest
import UniformTypeIdentifiers
@testable import HappaEcho

@MainActor
final class AttachmentThumbnailLoaderTests: XCTestCase {
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLXLwAAAABJRU5ErkJggg==")!
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testLoadsImageThumbnailFromStoredAttachment() async throws {
        let store = AttachmentStore(rootURL: root)
        let imported = try await store.importTransferredData(
            png,
            suggestedName: "fixture.png",
            contentType: .png,
            conversationID: UUID()
        )
        let attachment = imported.makeMessageAttachment(userOrder: 0)

        let image = await AttachmentThumbnailLoader(store: store).image(for: attachment)

        XCTAssertNotNil(image)
    }
}
