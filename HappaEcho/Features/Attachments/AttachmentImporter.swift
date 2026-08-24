import Foundation
import PhotosUI
import UniformTypeIdentifiers

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
        progress?(0)
        let provider = result.itemProvider
        guard let typeIdentifier = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }),
              let type = UTType(typeIdentifier) else { throw AttachmentStoreError.invalidImage }
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
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
