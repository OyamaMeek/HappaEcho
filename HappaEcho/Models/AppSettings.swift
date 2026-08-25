import Foundation
import SwiftData

/// Non-sensitive application settings. Secrets (chat API key and Notion token)
/// live only in Keychain and never in SwiftData.
@Model
final class AppSettings {
    /// OpenAI-compatible Chat Completions endpoint.
    var endpoint: String

    var modelID: String

    /// Whether the configured model accepts image input. Presets carry their
    /// default capability; custom models set this explicitly, never by name.
    var supportsVision: Bool

    /// Optional per-image Base64 byte cap; `nil` means no local check.
    var maxImageBytes: Int?

    /// Optional estimated request-body cap; `nil` means no local check.
    var maxRequestBodyBytes: Int?

    var systemPrompt: String?

    var notionEnabled: Bool
    var notionDatabaseID: String?

    init(
        endpoint: String = "https://api.openai.com/v1/chat/completions",
        modelID: String = "gpt-4o-mini",
        supportsVision: Bool = true,
        maxImageBytes: Int? = nil,
        maxRequestBodyBytes: Int? = nil,
        systemPrompt: String? = nil,
        notionEnabled: Bool = false,
        notionDatabaseID: String? = nil
    ) {
        self.endpoint = endpoint
        self.modelID = modelID
        self.supportsVision = supportsVision
        self.maxImageBytes = maxImageBytes
        self.maxRequestBodyBytes = maxRequestBodyBytes
        self.systemPrompt = systemPrompt
        self.notionEnabled = notionEnabled
        self.notionDatabaseID = notionDatabaseID
    }
}
