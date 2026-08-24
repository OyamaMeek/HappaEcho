import XCTest
import UniformTypeIdentifiers
import PhotosUI
@testable import HappaEcho

final class AttachmentStoreTests: XCTestCase {
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLXLwAAAABJRU5ErkJggg==")!
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appending(path: "HappaEcho-photo-staging", directoryHint: .isDirectory))
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

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
    func testPhotoFileProviderStagesExactBytesBeforeProviderFileExpiresAndReportsProgress() async throws {
        let provider = ControlledPhotoFileProvider(data: png, root: root, typeIdentifier: UTType.png.identifier)
        let importer = PhotoLibraryImporter(store: AttachmentStore(rootURL: root))
        var values: [Double] = []
        importer.progress = { values.append($0) }

        let task = Task { try await importer.importProvider(provider, conversationID: UUID()) }
        await provider.waitForLoad()
        XCTAssertEqual(values, [0])
        provider.reportProgress(25)
        try? await Task.sleep(for: .milliseconds(50))
        provider.reportProgress(75)
        try? await Task.sleep(for: .milliseconds(50))
        provider.completeAndDeleteSource()
        let attachment = try await task.value

        XCTAssertEqual(try Data(contentsOf: root.appending(path: attachment.relativePath)), png)
        XCTAssertEqual(values.first, 0)
        XCTAssertTrue(values.contains(0.75))
        XCTAssertEqual(values.last, 1)
        XCTAssertTrue(provider.sourceWasDeleted)
    }

    @MainActor
    func testPhotoImportCancellationCancelsUnderlyingTransferAndDoesNotPersistOrComplete() async throws {
        let provider = ControlledPhotoFileProvider(data: png, root: root, typeIdentifier: UTType.png.identifier)
        let importer = PhotoLibraryImporter(store: AttachmentStore(rootURL: root))
        var values: [Double] = []
        importer.progress = { values.append($0) }
        let task = Task { try await importer.importProvider(provider, conversationID: UUID()) }
        await provider.waitForLoad()
        try? await Task.sleep(for: .milliseconds(50))
        provider.reportProgress(25)
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
        provider.completeAndDeleteSource()
        try? await Task.sleep(for: .milliseconds(20))

        XCTAssertTrue(provider.progress.isCancelled)
        XCTAssertEqual(values, [0, 0.25])
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent != "photos-provider-source.png" }
            .isEmpty)
    }

    @MainActor
    func testPhotoFileProviderErrorDoesNotPersistOrComplete() async throws {
        let provider = ControlledPhotoFileProvider(data: png, root: root, typeIdentifier: UTType.png.identifier)
        let importer = PhotoLibraryImporter(store: AttachmentStore(rootURL: root))
        var values: [Double] = []
        importer.progress = { values.append($0) }
        let task = Task { try await importer.importProvider(provider, conversationID: UUID()) }
        await provider.waitForLoad()
        provider.fail()
        do { _ = try await task.value; XCTFail("Expected unreadable file") }
        catch AttachmentStoreError.unreadableFile { }
        XCTAssertEqual(values, [0])
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent != "photos-provider-source.png" }
            .isEmpty)
    }

    @MainActor
    func testCancellationAfterStoreImportDeletesPersistedAttachment() async throws {
        let provider = ControlledPhotoFileProvider(data: png, root: root, typeIdentifier: UTType.png.identifier)
        let gate = ImportGate()
        let persisted = ImportedAttachment(id: UUID(), originalFileName: "persisted.png", utType: UTType.png.identifier, mimeType: "image/png", pixelWidth: 1, pixelHeight: 1, fileSize: png.count, relativePath: "persisted.png")
        let importer = PhotoLibraryImporter(importFile: { _, _ in
            await gate.waitUntilReleased()
            return persisted
        }, deleteDraft: { attachment in await gate.recordDeletion(attachment) })
        let task = Task { try await importer.importProvider(provider, conversationID: UUID()) }
        await provider.waitForLoad()
        provider.completeAndDeleteSource()
        await gate.waitUntilImportBegins()
        task.cancel()
        await gate.release()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError { }
        let deleted = await gate.deleted
        XCTAssertEqual(deleted, [persisted])
    }

    @MainActor
    func testLateProviderCompletionAfterCancellationDoesNotRecreateStagingFile() async throws {
        let provider = ControlledPhotoFileProvider(data: png, root: root, typeIdentifier: UTType.png.identifier)
        let importer = PhotoLibraryImporter(store: AttachmentStore(rootURL: root))
        let task = Task { try await importer.importProvider(provider, conversationID: UUID()) }
        await provider.waitForLoad()
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError { }
        provider.completeAndDeleteSource()
        try? await Task.sleep(for: .milliseconds(25))
        let staging = FileManager.default.temporaryDirectory.appending(path: "HappaEcho-photo-staging", directoryHint: .isDirectory)
        let files = (try? FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)) ?? []
        XCTAssertFalse(files.contains { $0.lastPathComponent.hasSuffix(".png") })
    }

    @MainActor
    func testQueuedProgressIsNotDeliveredAfterCancellation() async throws {
        let provider = ControlledPhotoFileProvider(data: png, root: root, typeIdentifier: UTType.png.identifier)
        let importer = PhotoLibraryImporter(store: AttachmentStore(rootURL: root))
        var values: [Double] = []
        importer.progress = { values.append($0) }
        let task = Task { try await importer.importProvider(provider, conversationID: UUID()) }
        await provider.waitForLoad()
        provider.reportProgress(50)
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError { }
        try? await Task.sleep(for: .milliseconds(25))
        XCTAssertEqual(values, [0])
    }

    @MainActor
    func testPhotoPickerConfigurationUsesCurrentAssetRepresentation() {
        XCTAssertEqual(PhotoLibraryImporter.pickerConfiguration().preferredAssetRepresentationMode, .current)
    }

    @MainActor
    func testActualNSItemProviderFileRepresentationAdapterPreservesPNGBytes() async throws {
        let source = root.appending(path: "provider.png")
        try png.write(to: source)
        let provider = NSItemProvider(contentsOf: source, contentType: .png)
        let imported = try await PhotoLibraryImporter(store: AttachmentStore(rootURL: root)).importProvider(provider, conversationID: UUID())
        XCTAssertEqual(try Data(contentsOf: root.appending(path: imported.relativePath)), png)
    }

    func testSecurityScopedAccessReleasesAfterSuccessfulCopy() async throws {
        let source = root.appending(path: "source.png"); try png.write(to: source)
        let scope = RecordingSecurityScope()
        _ = try await AttachmentStore(rootURL: root, securityScope: scope).importFile(from: source, conversationID: UUID())
        XCTAssertEqual(scope.events, [.acquire(source), .release(source)])
    }

    func testSecurityScopedAccessReleasesAfterCopyError() async throws {
        let source = root.appending(path: "missing.png"); let scope = RecordingSecurityScope()
        do { _ = try await AttachmentStore(rootURL: root, securityScope: scope).importFile(from: source, conversationID: UUID()); XCTFail("Expected unreadable file") }
        catch AttachmentStoreError.unreadableFile { }
        XCTAssertEqual(scope.events, [.acquire(source), .release(source)])
    }

    func testInvalidTransferredDataDoesNotDeleteOtherDrafts() async throws {
        let store = AttachmentStore(rootURL: root); let conversationID = UUID()
        let valid = try await store.importTransferredData(png, suggestedName: "valid.png", contentType: .png, conversationID: conversationID)
        do { _ = try await store.importTransferredData(Data("not an image".utf8), suggestedName: "invalid.png", contentType: .png, conversationID: conversationID); XCTFail("Expected invalid image error") }
        catch AttachmentStoreError.invalidImage { }
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: valid.relativePath).path))
    }

    func testDeleteDraftAndOrphanCleanupRemoveOriginals() async throws {
        let store = AttachmentStore(rootURL: root); let conversationID = UUID()
        let first = try await store.importTransferredData(png, suggestedName: "first.png", contentType: .png, conversationID: conversationID)
        let second = try await store.importTransferredData(png, suggestedName: "second.png", contentType: .png, conversationID: conversationID)
        try await store.deleteDraft(first); try await store.removeOrphans(keeping: [second.relativePath])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: first.relativePath).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: second.relativePath).path))
    }
}

private final class ControlledPhotoFileProvider: PhotoFileRepresentationLoading, @unchecked Sendable {
    let suggestedName: String? = "icloud-fixture.png"
    let typeIdentifiers: [String]
    let progress = Progress(totalUnitCount: 100)
    private let lock = NSLock()
    private let source: URL
    private var completion: ((URL?, Error?) -> Void)?
    private var started = false
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var sourceWasDeleted = false

    init(data: Data, root: URL, typeIdentifier: String) {
        typeIdentifiers = [typeIdentifier]
        source = root.appending(path: "photos-provider-source.png")
        try! data.write(to: source)
    }

    func loadFileRepresentation(typeIdentifier: String, completion: @escaping (URL?, Error?) -> Void) -> Progress {
        lock.lock()
        self.completion = completion
        started = true
        continuation?.resume()
        continuation = nil
        lock.unlock()
        return progress
    }

    func waitForLoad() async {
        lock.lock()
        let alreadyStarted = started
        lock.unlock()
        guard !alreadyStarted else { return }
        await withCheckedContinuation { continuation in
            lock.lock()
            if started { lock.unlock(); continuation.resume() }
            else { self.continuation = continuation; lock.unlock() }
        }
    }

    func reportProgress(_ completed: Int64) { progress.completedUnitCount = completed }

    func completeAndDeleteSource() {
        lock.lock(); let callback = completion; lock.unlock()
        callback?(source, nil)
        try? FileManager.default.removeItem(at: source)
        sourceWasDeleted = true
    }

    func fail() { lock.lock(); let callback = completion; lock.unlock(); callback?(nil, nil) }
}

private actor ImportGate {
    private var importStarted = false
    private var released = false
    private var deletedAttachments: [ImportedAttachment] = []

    func waitUntilImportBegins() async {
        while !importStarted { await Task.yield() }
    }

    func waitUntilReleased() async {
        importStarted = true
        while !released { await Task.yield() }
    }

    func release() { released = true }
    func recordDeletion(_ attachment: ImportedAttachment) { deletedAttachments.append(attachment) }
    var deleted: [ImportedAttachment] { deletedAttachments }
}

private final class RecordingSecurityScope: SecurityScopedResourceAccessing, @unchecked Sendable {
    enum Event: Equatable { case acquire(URL); case release(URL) }
    private let lock = NSLock(); private var recordedEvents: [Event] = []
    var events: [Event] { lock.lock(); defer { lock.unlock() }; return recordedEvents }
    func acquire(_ url: URL) -> Bool { lock.lock(); recordedEvents.append(.acquire(url)); lock.unlock(); return true }
    func release(_ url: URL) { lock.lock(); recordedEvents.append(.release(url)); lock.unlock() }
}
