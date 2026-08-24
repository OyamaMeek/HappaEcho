import Foundation
import PhotosUI
import UniformTypeIdentifiers

protocol PhotoDataLoading: AnyObject {
    var suggestedName: String? { get }
    var typeIdentifiers: [String] { get }
    func loadData(typeIdentifier: String, completion: @escaping (Data?, Error?) -> Void)
}

extension NSItemProvider: PhotoDataLoading {
    var typeIdentifiers: [String] { registeredTypeIdentifiers }
    func loadData(typeIdentifier: String, completion: @escaping (Data?, Error?) -> Void) { loadDataRepresentation(forTypeIdentifier: typeIdentifier, completionHandler: completion) }
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
        return try await importProvider(result.itemProvider, conversationID: conversationID)
    }

    func importProvider(_ provider: any PhotoDataLoading, conversationID: UUID) async throws -> ImportedAttachment {
        progress?(0)
        guard let typeIdentifier = provider.typeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }),
              let type = UTType(typeIdentifier) else { throw AttachmentStoreError.invalidImage }
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            provider.loadData(typeIdentifier: typeIdentifier) { data, error in
                if let error { continuation.resume(throwing: error) }
                else if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: AttachmentStoreError.unreadableFile) }
            }
        }
        progress?(1)
        return try await store.importTransferredData(data, suggestedName: provider.suggestedName ?? "image.\(type.preferredFilenameExtension ?? "img")", contentType: type, conversationID: conversationID)
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
