import XCTest
import UniformTypeIdentifiers
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

    @MainActor
    func testPhotoProviderTransfersExactBytesAndReportsCompleteProgress() async throws {
        let provider = FixturePhotoDataLoader(data: png, suggestedName: "icloud-fixture.png", typeIdentifier: UTType.png.identifier, progressValues: [0.25, 0.75])
        let importer = PhotoLibraryImporter(store: AttachmentStore(rootURL: root))
        var progress: [Double] = []
        importer.progress = { progress.append($0) }

        let attachment = try await importer.importProvider(provider, conversationID: UUID())

        XCTAssertEqual(try Data(contentsOf: root.appending(path: attachment.relativePath)), png)
        XCTAssertEqual(progress, [0, 0.25, 0.75, 1])
    }

    @MainActor
    func testPhotoPickerConfigurationUsesCurrentAssetRepresentation() {
        XCTAssertEqual(PhotoLibraryImporter.pickerConfiguration().preferredAssetRepresentationMode, .current)
    }

    func testSecurityScopedAccessReleasesAfterSuccessfulCopy() async throws {
        let source = root.appending(path: "source.png")
        try png.write(to: source)
        let scope = RecordingSecurityScope()

        _ = try await AttachmentStore(rootURL: root, securityScope: scope).importFile(from: source, conversationID: UUID())

        XCTAssertEqual(scope.events, [.acquire(source), .release(source)])
    }

    func testSecurityScopedAccessReleasesAfterCopyError() async throws {
        let source = root.appending(path: "missing.png")
        let scope = RecordingSecurityScope()

        do {
            _ = try await AttachmentStore(rootURL: root, securityScope: scope).importFile(from: source, conversationID: UUID())
            XCTFail("Expected unreadable file")
        } catch AttachmentStoreError.unreadableFile { }

        XCTAssertEqual(scope.events, [.acquire(source), .release(source)])
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

private final class FixturePhotoDataLoader: PhotoDataLoading, PhotoProviderDataLoading, @unchecked Sendable {
    let data: Data
    let suggestedName: String?
    let typeIdentifiers: [String]
    let progressValues: [Double]

    init(data: Data, suggestedName: String, typeIdentifier: String, progressValues: [Double]) {
        self.data = data
        self.suggestedName = suggestedName
        self.typeIdentifiers = [typeIdentifier]
        self.progressValues = progressValues
    }

    func loadData(typeIdentifier: String, completion: @escaping (Data?, Error?) -> Void) {
        completion(data, nil)
    }

    func loadData(typeIdentifier: String, progress: @escaping (Double) -> Void, completion: @escaping (Data?, Error?) -> Void) {
        progressValues.forEach(progress)
        completion(data, nil)
    }
}

private final class RecordingSecurityScope: SecurityScopedResourceAccessing, @unchecked Sendable {
    enum Event: Equatable {
        case acquire(URL)
        case release(URL)
    }

    private let lock = NSLock()
    private var recordedEvents: [Event] = []

    var events: [Event] {
        lock.lock()
        defer { lock.unlock() }
        return recordedEvents
    }

    func acquire(_ url: URL) -> Bool {
        lock.lock()
        recordedEvents.append(.acquire(url))
        lock.unlock()
        return true
    }

    func release(_ url: URL) {
        lock.lock()
        recordedEvents.append(.release(url))
        lock.unlock()
    }
}
