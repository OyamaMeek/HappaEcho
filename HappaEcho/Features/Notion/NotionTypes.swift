import Foundation

protocol NotionService: Sendable {
    func createPage(_ request: NotionPageRequest) async throws -> NotionPage
    func updatePageProperties(pageID: String, properties: [String: NotionProperty]) async throws
    func appendBlocks(pageID: String, blocks: [NotionBlock]) async throws -> [String]
    func listBlocks(pageID: String, cursor: String?) async throws -> NotionBlockPage
    func createFileUpload(_ request: NotionFileUploadRequest) async throws -> NotionFileUpload
    func sendFile(uploadID: String, fileURL: URL) async throws
    func completeFileUpload(uploadID: String) async throws -> NotionFileUpload
}

enum NotionProperty: Equatable, Sendable {
    case title(String), richText(String), date(Date), number(Int), select(String)
}

struct NotionPageRequest: Sendable { var databaseID: String; var properties: [String: NotionProperty] }
struct NotionPage: Decodable, Sendable { var id: String; var url: URL?; var properties: [String: JSONValue] = [:] }
struct NotionFileUploadRequest: Sendable { var filename: String; var contentType: String }
struct NotionFileUpload: Decodable, Sendable { var id: String; var status: String; var file: File?; struct File: Decodable, Sendable { var url: URL? }; var fileURL: URL? { file?.url } }
struct NotionBlockPage: Sendable { var blocks: [NotionBlock]; var hasMore: Bool; var nextCursor: String? }

struct NotionBlockBatch: Equatable, Sendable { var index: Int; var marker: String; var blocks: [NotionBlock] }

struct NotionRichText: Codable, Equatable, Sendable { var content: String }

enum NotionBlockKind: Equatable, Sendable { case paragraph, heading(level: Int), bulletedListItem, quote, code(language: String) }

struct NotionBlock: Equatable, Sendable {
    var kind: NotionBlockKind
    var richText: [NotionRichText]
    var markerMessageID: UUID?
    var plainText: String { richText.map(\.content).joined() }
    static func paragraph(_ text: String) -> Self { .init(kind: .paragraph, richText: [.init(content: text)], markerMessageID: nil) }
}

enum NotionError: Error, Equatable, Sendable { case unauthorized, forbidden, notFound, rateLimited(retryAfter: TimeInterval?), server(statusCode: Int), invalidResponse, network(code: Int?) }

enum JSONValue: Decodable, Sendable { case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    init(from decoder: Decoder) throws { let c = try decoder.singleValueContainer(); if c.decodeNil() { self = .null } else if let v = try? c.decode(Bool.self) { self = .bool(v) } else if let v = try? c.decode(Double.self) { self = .number(v) } else if let v = try? c.decode(String.self) { self = .string(v) } else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) } else { self = .array(try c.decode([JSONValue].self)) } }
}
