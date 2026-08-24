import XCTest
@testable import HappaEcho

final class AttachmentStoreTests: XCTestCase {
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLXLwAAAABJRU5ErkJggg==")!
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testFileImportPreservesOriginalBytes() async throws {
        let source = root.appending(path: "source.png")
        try png.write(to: source)
        let imported = try await AttachmentStore(rootURL: root).importFile(from: source, conversationID: UUID())
        XCTAssertEqual(try Data(contentsOf: root.appending(path: imported.relativePath)), png)
    }

    func testCameraImportPreservesOriginalBytes() async throws {
        let imported = try await CameraImporter(store: AttachmentStore(rootURL: root)).importCapturedData(png, conversationID: UUID())
        XCTAssertEqual(try Data(contentsOf: root.appending(path: imported.relativePath)), png)
    }

    func testDeletionRejectsSymlinkOutsideAttachmentRoot() async throws {
        let outside = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try png.write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: root.appending(path: "link.png"), withDestinationURL: outside)
        let attachment = ImportedAttachment(id: UUID(), originalFileName: "link.png", utType: "public.png", mimeType: "image/png", pixelWidth: 1, pixelHeight: 1, fileSize: png.count, relativePath: "link.png")
        do { try await AttachmentStore(rootURL: root).deleteDraft(attachment); XCTFail("Expected containment error") }
        catch AttachmentStoreError.invalidRelativePath { }
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testTransferredDataPreservesOriginalBytesAndStoresRelativePath() async throws {
        let store = AttachmentStore(rootURL: root)
        let conversationID = UUID()

        let attachment = try await store.importTransferredData(png, suggestedName: "fixture.png", contentType: .png, conversationID: conversationID)

        XCTAssertEqual(try Data(contentsOf: root.appending(path: attachment.relativePath)), png)
        XCTAssertEqual(attachment.mimeType, "image/png")
        XCTAssertFalse(attachment.relativePath.hasPrefix("/"))
        XCTAssertFalse(attachment.relativePath.contains(".."))
    }

    func testInvalidTransferredDataDoesNotDeleteOtherDrafts() async throws {
        let store = AttachmentStore(rootURL: root)
        let conversationID = UUID()
        let valid = try await store.importTransferredData(png, suggestedName: "valid.png", contentType: .png, conversationID: conversationID)

        do {
            _ = try await store.importTransferredData(Data("not an image".utf8), suggestedName: "invalid.png", contentType: .png, conversationID: conversationID)
            XCTFail("Expected invalid image error")
        } catch AttachmentStoreError.invalidImage { }

        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: valid.relativePath).path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: root.appending(path: conversationID.uuidString), includingPropertiesForKeys: nil).count, 1)
    }

    func testDeleteDraftAndOrphanCleanupRemoveOriginals() async throws {
        let store = AttachmentStore(rootURL: root)
        let conversationID = UUID()
        let first = try await store.importTransferredData(png, suggestedName: "first.png", contentType: .png, conversationID: conversationID)
        let second = try await store.importTransferredData(png, suggestedName: "second.png", contentType: .png, conversationID: conversationID)

        try await store.deleteDraft(first)
        try await store.removeOrphans(keeping: [second.relativePath])

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: first.relativePath).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: second.relativePath).path))
    }
}
