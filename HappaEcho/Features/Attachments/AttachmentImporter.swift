import Foundation
import PhotosUI
import UniformTypeIdentifiers

protocol PhotoFileRepresentationLoading: AnyObject {
    var suggestedName: String? { get }
    var typeIdentifiers: [String] { get }
    @discardableResult func loadFileRepresentation(typeIdentifier: String, completion: @escaping (URL?, Error?) -> Void) -> Progress
}

extension NSItemProvider: PhotoFileRepresentationLoading {
    var typeIdentifiers: [String] { registeredTypeIdentifiers }
    func loadFileRepresentation(typeIdentifier: String, completion: @escaping (URL?, Error?) -> Void) -> Progress {
        loadFileRepresentation(forTypeIdentifier: typeIdentifier, completionHandler: completion)
    }
}

@MainActor
final class PhotoLibraryImporter: NSObject {
    var progress: ((Double) -> Void)?
    private let importFileOperation: @Sendable (URL, UUID) async throws -> ImportedAttachment
    private let deleteDraftOperation: @Sendable (ImportedAttachment) async -> Void

    init(store: AttachmentStore) {
        importFileOperation = { url, conversationID in try await store.importFile(from: url, conversationID: conversationID) }
        deleteDraftOperation = { attachment in try? await store.deleteDraft(attachment) }
    }

    init(importFile: @escaping @Sendable (URL, UUID) async throws -> ImportedAttachment, deleteDraft: @escaping @Sendable (ImportedAttachment) async -> Void) {
        importFileOperation = importFile
        deleteDraftOperation = deleteDraft
    }

    static func pickerConfiguration() -> PHPickerConfiguration {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.preferredAssetRepresentationMode = .current
        return configuration
    }

    func importResult(_ result: PHPickerResult, conversationID: UUID) async throws -> ImportedAttachment {
        try await importProvider(result.itemProvider, conversationID: conversationID)
    }

    func importProvider(_ provider: any PhotoFileRepresentationLoading, conversationID: UUID) async throws -> ImportedAttachment {
        guard let typeIdentifier = provider.typeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }),
              let type = UTType(typeIdentifier) else { throw AttachmentStoreError.invalidImage }
        progress?(0)
        let stagingURL = FileManager.default.temporaryDirectory.appending(path: "HappaEcho-photo-staging", directoryHint: .isDirectory).appending(path: UUID().uuidString + "." + (type.preferredFilenameExtension ?? "img"))
        try FileManager.default.createDirectory(at: stagingURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let state = PhotoTransferState(stagingURL: stagingURL) { [weak self] value in self?.progress?(value) }
        defer { state.cleanup() }
        let staged = try await withTaskCancellationHandler(operation: {
            try await state.load(provider: provider, typeIdentifier: typeIdentifier)
        }, onCancel: { state.cancel() })
        var imported: ImportedAttachment?
        do {
            let attachment = try await importFileOperation(staged, conversationID)
            imported = attachment
            try Task.checkCancellation()
            progress?(1)
            return attachment
        } catch {
            if let imported { await deleteDraftOperation(imported) }
            throw error
        }
    }
}

private final class PhotoTransferState: @unchecked Sendable {
    private let lock = NSLock()
    private let stagingURL: URL
    private var active = true
    private var generation = 0
    private var continuation: CheckedContinuation<URL, Error>?
    private var progress: Progress?
    private var observation: NSKeyValueObservation?
    private let report: @MainActor (Double) -> Void

    init(stagingURL: URL, report: @escaping @MainActor (Double) -> Void) { self.stagingURL = stagingURL; self.report = report }

    func load(provider: any PhotoFileRepresentationLoading, typeIdentifier: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock(); guard active else { lock.unlock(); continuation.resume(throwing: CancellationError()); return }; self.continuation = continuation; lock.unlock()
            let returnedProgress = provider.loadFileRepresentation(typeIdentifier: typeIdentifier) { [weak self] url, error in self?.complete(url: url, error: error) }
            register(returnedProgress)
        }
    }

    func cancel() { terminate(.failure(CancellationError()), cancelProgress: true) }

    func cleanup() {
        lock.lock(); active = false; generation += 1; let observation = observation; self.observation = nil; try? FileManager.default.removeItem(at: stagingURL); lock.unlock()
        observation?.invalidate()
    }

    // The lock protects both active state and the synchronous provider-file copy.
    private func complete(url: URL?, error: Error?) {
        lock.lock()
        guard active else { lock.unlock(); return }
        let result: Result<URL, Error>
        if let error { result = .failure(error) }
        else if let url { do { try FileManager.default.copyItem(at: url, to: stagingURL); result = .success(stagingURL) } catch { result = .failure(AttachmentStoreError.unreadableFile) } }
        else { result = .failure(AttachmentStoreError.unreadableFile) }
        active = false; generation += 1
        let observation = observation; self.observation = nil; let continuation = continuation; self.continuation = nil; progress = nil
        lock.unlock(); observation?.invalidate(); continuation?.resume(with: result)
    }

    private func terminate(_ result: Result<URL, Error>, cancelProgress: Bool) {
        lock.lock(); guard active else { lock.unlock(); return }
        active = false; generation += 1
        let progress = progress; let observation = observation; self.observation = nil; let continuation = continuation; self.continuation = nil
        try? FileManager.default.removeItem(at: stagingURL)
        lock.unlock(); observation?.invalidate(); if cancelProgress { progress?.cancel() }; continuation?.resume(with: result)
    }

    private func register(_ progress: Progress) {
        lock.lock(); guard active else { lock.unlock(); progress.cancel(); return }; self.progress = progress; let token = generation; lock.unlock()
        let observation = progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
            Task { @MainActor [weak self] in self?.reportIfCurrent(progress.fractionCompleted, token: token) }
        }
        lock.lock(); if active { self.observation = observation; lock.unlock() } else { lock.unlock(); observation.invalidate(); progress.cancel() }
    }

    @MainActor private func reportIfCurrent(_ value: Double, token: Int) {
        lock.lock(); let deliver = active && generation == token; lock.unlock()
        if deliver { report(value) }
    }
}

@MainActor
final class CameraImporter {
    private let store: AttachmentStore
    init(store: AttachmentStore) { self.store = store }
    func importCapturedData(_ data: Data, suggestedName: String = "camera.jpg", contentType: UTType = .jpeg, conversationID: UUID) async throws -> ImportedAttachment {
        try await store.importTransferredData(data, suggestedName: suggestedName, contentType: contentType, conversationID: conversationID)
    }
}
