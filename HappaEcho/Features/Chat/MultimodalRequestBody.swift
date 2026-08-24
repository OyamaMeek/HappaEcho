import Foundation

struct PreparedHTTPBody: @unchecked Sendable {
    let fileURL: URL
    let contentLength: Int64
    let contentType: String
    let cleanup: @Sendable () -> Void

    /// Creates a new stream each time, including retries and redirects.
    func openStream() -> InputStream? { InputStream(url: fileURL) }
}

struct MultimodalRequestBodyLimits: Sendable {
    var maxImageBytes: Int?
    var maxRequestBodyBytes: Int?
    init(maxImageBytes: Int? = nil, maxRequestBodyBytes: Int? = nil) { self.maxImageBytes = maxImageBytes; self.maxRequestBodyBytes = maxRequestBodyBytes }
}

enum MultimodalRequestBodyError: Error, Equatable {
    case imageTooLarge(index: Int)
    case requestTooLarge
    case unreadableAttachment
}

struct MultimodalRequestBody {
    let request: ChatRequest
    /// Attachments indexed by request message; each inner array preserves the user's selection order.
    let attachmentsByMessage: [[MessageAttachment]]
    let limits: MultimodalRequestBodyLimits
    let attachmentRootURL: URL?

    init(request: ChatRequest, attachmentsByMessage: [[MessageAttachment]], limits: MultimodalRequestBodyLimits = .init(), attachmentRootURL: URL? = nil) {
        self.request = request
        self.attachmentsByMessage = attachmentsByMessage
        self.limits = limits
        self.attachmentRootURL = attachmentRootURL
    }

    func prepareTemporaryFile() async throws -> PreparedHTTPBody {
        let estimatedLength = try validateLimits()
        if let limit = limits.maxRequestBodyBytes, estimatedLength > limit { throw MultimodalRequestBodyError.requestTooLarge }
        let url = FileManager.default.temporaryDirectory.appending(path: "HappaEcho-request-\(UUID().uuidString).json")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        do {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try write("{\"model\":\(try json(request.model)),\"messages\":[", to: handle)
            for messageIndex in request.messages.indices {
                if messageIndex > 0 { try write(",", to: handle) }
                let message = request.messages[messageIndex]
                try write("{\"role\":\(try json(message.role.rawValue)),\"content\":[", to: handle)
                var needsComma = false
                for part in message.content {
                    if needsComma { try write(",", to: handle) }
                    try write(try jsonPart(part), to: handle)
                    needsComma = true
                }
                if messageIndex < attachmentsByMessage.count {
                    for attachment in attachmentsByMessage[messageIndex].sorted(by: { $0.userOrder < $1.userOrder }) {
                        if needsComma { try write(",", to: handle) }
                        try write("{\"type\":\"image_url\",\"image_url\":{\"url\":\"data:\(attachment.mimeType);base64,", to: handle)
                        try streamBase64(from: try resolvedURL(for: attachment), to: handle)
                        try write("\"}}", to: handle)
                        needsComma = true
                    }
                }
                try write("]}", to: handle)
            }
            try write("],\"stream\":true}", to: handle)
            let length = try handle.offset()
            if let limit = limits.maxRequestBodyBytes, length > UInt64(limit) { throw MultimodalRequestBodyError.requestTooLarge }
            return PreparedHTTPBody(fileURL: url, contentLength: Int64(length), contentType: "application/json", cleanup: { try? FileManager.default.removeItem(at: url) })
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    private func validateLimits() throws -> Int {
        var imageIndex = 0
        var base64Bytes = 0
        for attachments in attachmentsByMessage {
            for attachment in attachments.sorted(by: { $0.userOrder < $1.userOrder }) {
                let values = try? resolvedURL(for: attachment).resourceValues(forKeys: [.fileSizeKey])
                guard let size = values?.fileSize else { throw MultimodalRequestBodyError.unreadableAttachment }
                if let limit = limits.maxImageBytes, size > limit { throw MultimodalRequestBodyError.imageTooLarge(index: imageIndex) }
                guard size <= Int.max - 2 else { throw MultimodalRequestBodyError.requestTooLarge }
                let encoded = ((size + 2) / 3) * 4
                guard encoded <= Int.max - base64Bytes else { throw MultimodalRequestBodyError.requestTooLarge }
                base64Bytes += encoded
                imageIndex += 1
            }
        }
        // All JSON overhead is non-negative; this conservative lower bound prevents output creation for configured caps.
        return base64Bytes
    }

    private func resolvedURL(for attachment: MessageAttachment) throws -> URL {
        guard !attachment.relativePath.hasPrefix("/") else { throw MultimodalRequestBodyError.unreadableAttachment }
        let root = (attachmentRootURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "HappaEcho/Attachments", directoryHint: .isDirectory)).standardizedFileURL
        let url = root.appending(path: attachment.relativePath).standardizedFileURL
        guard url.path.hasPrefix(root.path + "/") else { throw MultimodalRequestBodyError.unreadableAttachment }
        return url
    }

    private func streamBase64(from url: URL, to handle: FileHandle) throws {
        guard let stream = InputStream(url: url) else { throw MultimodalRequestBodyError.unreadableAttachment }
        stream.open()
        defer { stream.close() }
        var remainder = Data()
        var buffer = [UInt8](repeating: 0, count: 48 * 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { throw stream.streamError ?? MultimodalRequestBodyError.unreadableAttachment }
            guard count > 0 else { break }
            remainder.append(buffer, count: count)
            let encodableCount = remainder.count - (remainder.count % 3)
            if encodableCount > 0 {
                try write(remainder.prefix(encodableCount).base64EncodedString(), to: handle)
                remainder.removeFirst(encodableCount)
            }
        }
        if !remainder.isEmpty { try write(remainder.base64EncodedString(), to: handle) }
    }

    private func jsonPart(_ part: ChatContentPart) throws -> String {
        String(decoding: try JSONEncoder().encode(part), as: UTF8.self)
    }

    private func json(_ string: String) throws -> String {
        String(decoding: try JSONEncoder().encode(string), as: UTF8.self)
    }

    private func write(_ string: String, to handle: FileHandle) throws {
        try handle.write(contentsOf: Data(string.utf8))
    }
}
