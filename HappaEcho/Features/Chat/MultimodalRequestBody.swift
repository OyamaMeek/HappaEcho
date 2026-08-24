import Foundation

struct PreparedHTTPBody: @unchecked Sendable {
    let fileURL: URL
    let contentLength: Int64
    let contentType: String
    let cleanup: @Sendable () -> Void

    private var streamProvider: FileBodyStreamProvider { FileBodyStreamProvider(fileURL: fileURL) }

    /// Creates a new stream each time, including retries and redirects.
    func openStream() -> InputStream? { streamProvider.makeBodyStream() }
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
    /// Injection point for deterministic tests; production defaults to the system temporary directory.
    let temporaryDirectory: URL

    init(request: ChatRequest, attachmentsByMessage: [[MessageAttachment]], limits: MultimodalRequestBodyLimits = .init(), attachmentRootURL: URL? = nil, temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
        self.request = request
        self.attachmentsByMessage = attachmentsByMessage
        self.limits = limits
        self.attachmentRootURL = attachmentRootURL
        self.temporaryDirectory = temporaryDirectory
    }

    func prepareTemporaryFile() async throws -> PreparedHTTPBody {
        // This is deliberately completed before even allocating the temporary path.
        // It uses the same tokens as the writer, so a configured cap is enforced
        // against the final JSON rather than a Base64-only estimate.
        try validateImageLimits()
        let finalLength = try exactSerializedLength()
        if let limit = limits.maxRequestBodyBytes, finalLength > Int64(limit) { throw MultimodalRequestBodyError.requestTooLarge }
        let url = temporaryDirectory.appending(path: "HappaEcho-request-\(UUID().uuidString).json")
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
                        try write("{\"type\":\"image_url\",\"image_url\":{\"url\":\"data:\(try json(attachment.mimeType).dropFirst().dropLast());base64,", to: handle)
                        try streamBase64(from: try resolvedURL(for: attachment), to: handle)
                        try write("\"}}", to: handle)
                        needsComma = true
                    }
                }
                try write("]}", to: handle)
            }
            try write("],\"stream\":true}", to: handle)
            let length = try handle.offset()
            guard length == UInt64(finalLength) else { throw MultimodalRequestBodyError.unreadableAttachment }
            return PreparedHTTPBody(fileURL: url, contentLength: finalLength, contentType: "application/json", cleanup: { try? FileManager.default.removeItem(at: url) })
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    private func validateImageLimits() throws {
        var imageIndex = 0
        for attachments in attachmentsByMessage {
            for attachment in attachments.sorted(by: { $0.userOrder < $1.userOrder }) {
                let values = try? resolvedURL(for: attachment).resourceValues(forKeys: [.fileSizeKey])
                guard let size = values?.fileSize else { throw MultimodalRequestBodyError.unreadableAttachment }
                if let limit = limits.maxImageBytes, size > limit { throw MultimodalRequestBodyError.imageTooLarge(index: imageIndex) }
                imageIndex += 1
            }
        }
    }


    private func exactSerializedLength() throws -> Int64 {
        var total: Int64 = try byteCount("{\"model\":\(try json(request.model)),\"messages\":[")
        var imageIndex = 0
        for messageIndex in request.messages.indices {
            if messageIndex > 0 { total = try adding(total, 1) }
            let message = request.messages[messageIndex]
            total = try adding(total, try byteCount("{\"role\":\(try json(message.role.rawValue)),\"content\":["))
            var needsComma = false
            for part in message.content {
                if needsComma { total = try adding(total, 1) }
                total = try adding(total, try byteCount(jsonPart(part)))
                needsComma = true
            }
            if messageIndex < attachmentsByMessage.count {
                for attachment in attachmentsByMessage[messageIndex].sorted(by: { $0.userOrder < $1.userOrder }) {
                    if needsComma { total = try adding(total, 1) }
                    // json(mime) has its surrounding quotes removed because it is embedded
                    // in a quoted data URL; this preserves every JSON escape byte exactly.
                    total = try adding(total, try byteCount("{\"type\":\"image_url\",\"image_url\":{\"url\":\"data:\(try json(attachment.mimeType).dropFirst().dropLast());base64,"))
                    let values = try? resolvedURL(for: attachment).resourceValues(forKeys: [.fileSizeKey])
                    guard let size = values?.fileSize else { throw MultimodalRequestBodyError.unreadableAttachment }
                    if let limit = limits.maxImageBytes, size > limit { throw MultimodalRequestBodyError.imageTooLarge(index: imageIndex) }
                    guard size <= ((Int.max / 4) * 3) else { throw MultimodalRequestBodyError.requestTooLarge }
                    total = try adding(total, Int64(((size + 2) / 3) * 4))
                    total = try adding(total, 3) // "}}
                    imageIndex += 1
                    needsComma = true
                }
            }
            total = try adding(total, 2) // ]}
        }
        return try adding(total, try byteCount("],\"stream\":true}"))
    }

    private func byteCount(_ string: String) throws -> Int64 {
        let count = string.lengthOfBytes(using: .utf8)
        guard count <= Int64.max else { throw MultimodalRequestBodyError.requestTooLarge }
        return Int64(count)
    }

    private func adding(_ lhs: Int64, _ rhs: Int64) throws -> Int64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else { throw MultimodalRequestBodyError.requestTooLarge }
        return sum
    }

    private func resolvedURL(for attachment: MessageAttachment) throws -> URL {
        guard !attachment.relativePath.hasPrefix("/") else { throw MultimodalRequestBodyError.unreadableAttachment }
        let root = (attachmentRootURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "HappaEcho/Attachments", directoryHint: .isDirectory)).standardizedFileURL
        let url = root.appending(path: attachment.relativePath).standardizedFileURL
        guard url.path.hasPrefix(root.path + "/"),
              url.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/") else { throw MultimodalRequestBodyError.unreadableAttachment }
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
