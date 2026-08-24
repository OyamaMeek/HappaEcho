import Foundation

/// The speaker of a request message on the wire.
///
/// Deliberately distinct from the persisted `MessageRole`: the transport needs
/// `.system` for instructions, which the store model must never persist, and
/// keeping the wire roles separate keeps these DTOs transport-focused.
enum ChatRole: String, Codable, Equatable, Sendable {
    case system
    case user
    case assistant
}

/// One content part of an input message in the OpenAI-compatible multimodal
/// `content` array.
enum ChatContentPart: Codable, Equatable, Sendable {
    case text(String)
    case image(ImagePart)

    struct ImagePart: Codable, Equatable, Sendable {
        /// Image MIME type used in the Data URL, e.g. `image/png`.
        var mimeType: String
        /// Base64-encoded image bytes for the `data:` URL.
        ///
        /// The attachment pipeline (Task 5) supplies this by streaming the
        /// original from disk, so the DTO never forces the transport to load
        /// originals into memory.
        var base64: String
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }

    private enum ImageURLKeys: String, CodingKey {
        case url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try container.decode(String.self, forKey: .text))
        case "image_url":
            let imageContainer = try container.nestedContainer(keyedBy: ImageURLKeys.self, forKey: .imageURL)
            let url = try imageContainer.decode(String.self, forKey: .url)
            self = .image(try Self.imagePart(fromDataURL: url))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown content part type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let image):
            try container.encode("image_url", forKey: .type)
            var imageContainer = container.nestedContainer(keyedBy: ImageURLKeys.self, forKey: .imageURL)
            try imageContainer.encode("data:\(image.mimeType);base64,\(image.base64)", forKey: .url)
        }
    }

    private static func imagePart(fromDataURL url: String) throws -> ImagePart {
        guard url.hasPrefix("data:") else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid image data URL"))
        }
        let remainder = url.dropFirst("data:".count)
        guard let base64Range = remainder.range(of: ";base64,") else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Missing base64 marker in image data URL"))
        }
        let mimeType = String(remainder[..<base64Range.lowerBound])
        let base64 = String(remainder[base64Range.upperBound...])
        return ImagePart(mimeType: mimeType, base64: base64)
    }
}

/// One input message in the ordered request `messages` array. Every message is
/// encoded exactly once in the order the caller provides.
struct ChatInputMessage: Codable, Equatable, Sendable {
    var role: ChatRole
    var content: [ChatContentPart]
}

/// The request for a streaming chat completion. Callers prepend a `.system`
/// message for the optional system prompt; the client encodes `messages`
/// verbatim, never duplicating or reordering them.
struct ChatRequest: Codable, Equatable, Sendable {
    var model: String
    var messages: [ChatInputMessage]
}

/// The request for a non-streaming short completion used to generate a
/// conversation title.
struct TitleRequest: Codable, Equatable, Sendable {
    var model: String
    var messages: [ChatInputMessage]
}

/// Stable domain errors surfaced by the chat transport. Views and controllers
/// switch on these cases rather than interpreting raw HTTP responses.
enum ChatServiceError: Error, Equatable {
    /// Endpoint or API key is missing or empty.
    case invalidConfiguration
    /// The request body was rejected (HTTP 400).
    case invalidRequest(message: String?)
    /// Authentication failed (HTTP 401/403).
    case unauthorized(message: String?)
    /// Rate limited (HTTP 429).
    case rateLimited(message: String?)
    /// Provider or server failure (HTTP 5xx).
    case serverError(message: String?)
    /// The response was not a valid HTTP response or had an unexpected shape
    /// (for example malformed delta JSON or an empty completion).
    case invalidResponse
    /// A transport-level failure (URLError).
    case network(code: Int?)
    /// An HTTP status the client does not otherwise classify.
    case unexpectedStatusCode(statusCode: Int, message: String?)
}
