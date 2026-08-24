import Foundation
import SwiftData

/// Metadata for an imported original image. Image bytes live in Application
/// Support; SwiftData stores only metadata and the sandbox-relative path.
@Model
final class MessageAttachment {
    @Attribute(.unique) var id: UUID

    /// User-visible selection order within the message.
    var userOrder: Int

    var originalFileName: String
    var utType: String
    var mimeType: String
    var pixelWidth: Int
    var pixelHeight: Int
    var fileSize: Int

    /// Sandbox-relative path under `Application Support/HappaEcho/Attachments`.
    var relativePath: String

    // MARK: Notion upload checkpoint fields

    var syncState: SyncState
    var notionUploadID: String?
    var notionRemoteURL: String?
    var notionImageBlockID: String?
    var syncError: String?

    var message: Message?

    init(
        id: UUID = UUID(),
        userOrder: Int,
        originalFileName: String,
        utType: String,
        mimeType: String,
        pixelWidth: Int,
        pixelHeight: Int,
        fileSize: Int,
        relativePath: String,
        syncState: SyncState = .pending,
        notionUploadID: String? = nil,
        notionRemoteURL: String? = nil,
        notionImageBlockID: String? = nil,
        syncError: String? = nil
    ) {
        self.id = id
        self.userOrder = userOrder
        self.originalFileName = originalFileName
        self.utType = utType
        self.mimeType = mimeType
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.fileSize = fileSize
        self.relativePath = relativePath
        self.syncState = syncState
        self.notionUploadID = notionUploadID
        self.notionRemoteURL = notionRemoteURL
        self.notionImageBlockID = notionImageBlockID
        self.syncError = syncError
    }
}
