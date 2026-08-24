import Foundation
import PhotosUI
import UniformTypeIdentifiers

protocol PhotoFileRepresentationLoading: AnyObject {
    var suggestedName: String? { get }
    var typeIdentifiers: [String] { get }
    @discardableResult
    func loadFileRepresentation(typeIdentifier: String, completion: @escaping (URL?, Error?) -> Void) -> Progress
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
    private let store: AttachmentStore

    init(store: AttachmentStore) { self.store = store }

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
        let stagingURL = FileManager.default.temporaryDirectory
            .appending(path: "HappaEcho-photo-staging", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString + "." + (type.preferredFilenameExtension ?? "img"))
        try FileManager.default.createDirectory(at: stagingURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stagingURL) }

        let state = PhotoTransferState { [weak self] fraction in
            Task { @MainActor [weak self] in self?.progress?(fraction) }
        }
        let transferredURL = try await withTaskCancellationHandler(operation: {
            try await state.load(provider: provider, typeIdentifier: typeIdentifier, stagingURL: stagingURL)
        }, onCancel: {
            state.cancel()
        })
        try Task.checkCancellation()
        let attachment = try await store.importFile(from: transferredURL, conversationID: conversationID)
        try Task.checkCancellation()
        progress?(1)
        return attachment
    }
}

private final class PhotoTransferState: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true
    private var continuation: CheckedContinuation<URL, Error>?
    private var progress: Progress?
    private var observation: NSKeyValueObservation?
    private let report: (Double) -> Void

    init(report: @escaping (Double) -> Void) { self.report = report }

    func load(provider: any PhotoFileRepresentationLoading, typeIdentifier: String, stagingURL: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            guard active else { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
            self.continuation = continuation
            lock.unlock()

            let providerProgress = provider.loadFileRepresentation(typeIdentifier: typeIdentifier) { [weak self] providerURL, error in
                guard let self else { return }
                // This copy intentionally completes before the Photos callback returns.
                if let error { self.finish(.failure(error)); return }
                guard let providerURL else { self.finish(.failure(AttachmentStoreError.unreadableFile)); return }
                do {
                    try FileManager.default.copyItem(at: providerURL, to: stagingURL)
                    self.finish(.success(stagingURL))
                } catch {
                    self.finish(.failure(AttachmentStoreError.unreadableFile))
                }
            }
            register(progress: providerProgress)
        }
    }

    func cancel() {
        lock.lock()
        guard active else { lock.unlock(); return }
        active = false
        let progress = progress
        let observation = observation
        self.observation = nil
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        observation?.invalidate()
        progress?.cancel()
        continuation?.resume(throwing: CancellationError())
    }

    private func register(progress: Progress) {
        lock.lock()
        guard active else { lock.unlock(); progress.cancel(); return }
        self.progress = progress
        lock.unlock()

        let observation = progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
            self?.reportProgress(progress.fractionCompleted)
        }
        lock.lock()
        if active { self.observation = observation }
        else { lock.unlock(); observation.invalidate(); progress.cancel(); return }
        lock.unlock()
    }

    private func reportProgress(_ fraction: Double) {
        lock.lock()
        let shouldReport = active
        lock.unlock()
        if shouldReport { report(fraction) }
    }

    private func finish(_ result: Result<URL, Error>) {
        lock.lock()
        guard active else { lock.unlock(); return }
        active = false
        let observation = observation
        self.observation = nil
        let continuation = continuation
        self.continuation = nil
        progress = nil
        lock.unlock()
        observation?.invalidate()
        continuation?.resume(with: result)
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
