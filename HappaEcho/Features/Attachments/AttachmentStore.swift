import Foundation
import UniformTypeIdentifiers
import ImageIO

struct ImportedAttachment: Sendable, Equatable {
    let id: UUID
    let originalFileName: String
    let utType: String
    let mimeType: String
    let pixelWidth: Int
    let pixelHeight: Int
    let fileSize: Int
    let relativePath: String

    func makeMessageAttachment(userOrder: Int) -> MessageAttachment {
        MessageAttachment(id: id, userOrder: userOrder, originalFileName: originalFileName, utType: utType, mimeType: mimeType, pixelWidth: pixelWidth, pixelHeight: pixelHeight, fileSize: fileSize, relativePath: relativePath)
    }
}

enum AttachmentStoreError: Error, Equatable {
    case invalidImage
    case invalidRelativePath
    case unreadableFile
}

protocol SecurityScopedResourceAccessing: Sendable {
    func acquire(_ url: URL) -> Bool
    func release(_ url: URL)
}

struct URLSecurityScope: SecurityScopedResourceAccessing {
    func acquire(_ url: URL) -> Bool { url.startAccessingSecurityScopedResource() }
    func release(_ url: URL) { url.stopAccessingSecurityScopedResource() }
}

actor AttachmentStore {
    let rootURL: URL
    private let fileManager: FileManager
    private let securityScope: any SecurityScopedResourceAccessing

    init(rootURL: URL? = nil, fileManager: FileManager = .default, securityScope: any SecurityScopedResourceAccessing = URLSecurityScope()) {
        self.fileManager = fileManager
        self.securityScope = securityScope
        self.rootURL = rootURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "HappaEcho/Attachments", directoryHint: .isDirectory)
    }

    func importFile(from sourceURL: URL, conversationID: UUID) async throws -> ImportedAttachment {
        let accessed = securityScope.acquire(sourceURL)
        defer { if accessed { securityScope.release(sourceURL) } }
        let name = sourceURL.lastPathComponent.isEmpty ? "image" : sourceURL.lastPathComponent
        let contentType = UTType(filenameExtension: sourceURL.pathExtension) ?? .image
        let destination = try destinationURL(conversationID: conversationID, name: name, contentType: contentType)
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = destination.deletingLastPathComponent().appending(path: ".\(UUID().uuidString).import")
        do {
            try Data(contentsOf: sourceURL, options: .mappedIfSafe).write(to: temporary, options: .atomic)
            try fileManager.moveItem(at: temporary, to: destination)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw AttachmentStoreError.unreadableFile
        }
        return try validateAndDescribe(destination: destination, conversationID: conversationID, originalName: name, fallbackType: contentType)
    }

    func importTransferredData(_ data: Data, suggestedName: String, contentType: UTType, conversationID: UUID) async throws -> ImportedAttachment {
        let destination = try destinationURL(conversationID: conversationID, name: suggestedName, contentType: contentType)
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
        return try validateAndDescribe(destination: destination, conversationID: conversationID, originalName: suggestedName, fallbackType: contentType)
    }

    func deleteDraft(_ attachment: ImportedAttachment) throws {
        let url = try resolvedURL(for: attachment.relativePath)
        try? fileManager.removeItem(at: url)
    }

    func data(for attachment: MessageAttachment) throws -> Data {
        try Data(contentsOf: resolvedURL(for: attachment.relativePath), options: .mappedIfSafe)
    }

    func deleteDraft(_ attachment: MessageAttachment) throws {
        let url = try resolvedURL(for: attachment.relativePath)
        try? fileManager.removeItem(at: url)
    }

    func removeOrphans(keeping relativePaths: Set<String>) throws {
        guard fileManager.fileExists(atPath: rootURL.path) else { return }
        let allowed = Set(try relativePaths.map { try resolvedURL(for: $0).standardizedFileURL.path })
        let files = fileManager.enumerator(at: rootURL, includingPropertiesForKeys: [.isRegularFileKey])
        while let url = files?.nextObject() as? URL {
            if !(try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile ?? false) { continue }
            if !allowed.contains(url.standardizedFileURL.path) { try fileManager.removeItem(at: url) }
        }
    }

    func removeOrphans(keeping relativePaths: [String]) throws { try removeOrphans(keeping: Set(relativePaths)) }

    private func destinationURL(conversationID: UUID, name: String, contentType: UTType) throws -> URL {
        let safeName = URL(fileURLWithPath: name).lastPathComponent
        guard !safeName.isEmpty, safeName != ".", safeName != ".." else { throw AttachmentStoreError.invalidRelativePath }
        let ext = URL(fileURLWithPath: safeName).pathExtension
        let fileName = "\(UUID().uuidString)\(ext.isEmpty ? ".\(contentType.preferredFilenameExtension ?? "img")" : ".\(ext)")"
        return rootURL.appending(path: conversationID.uuidString, directoryHint: .isDirectory).appending(path: fileName)
    }

    private func validateAndDescribe(destination: URL, conversationID: UUID, originalName: String, fallbackType: UTType) throws -> ImportedAttachment {
        guard let source = CGImageSourceCreateWithURL(destination as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
            try? fileManager.removeItem(at: destination)
            throw AttachmentStoreError.invalidImage
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard width > 0, height > 0 else { try? fileManager.removeItem(at: destination); throw AttachmentStoreError.invalidImage }
        let detectedType = CGImageSourceGetType(source).flatMap { UTType($0 as String) } ?? fallbackType
        guard let mime = detectedType.preferredMIMEType,
              (try? JSONEncoder().encode(mime)) != nil else { try? fileManager.removeItem(at: destination); throw AttachmentStoreError.invalidImage }
        let size = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let relative = destination.path.replacingOccurrences(of: rootURL.path + "/", with: "")
        return ImportedAttachment(id: UUID(), originalFileName: originalName, utType: detectedType.identifier, mimeType: mime, pixelWidth: width, pixelHeight: height, fileSize: size, relativePath: relative)
    }

    private func resolvedURL(for relativePath: String) throws -> URL {
        let root = rootURL.standardizedFileURL
        guard !relativePath.hasPrefix("/") else { throw AttachmentStoreError.invalidRelativePath }
        let url = root.appending(path: relativePath).standardizedFileURL
        guard url.path.hasPrefix(root.path + "/"),
              url.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/") else { throw AttachmentStoreError.invalidRelativePath }
        return url
    }
}
