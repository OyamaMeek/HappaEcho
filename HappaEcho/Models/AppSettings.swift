import Foundation
import SwiftData

/// Non-sensitive application settings. Secrets (chat API key and Notion token)
/// live only in Keychain and never in SwiftData.
@Model
final class AppSettings {
    var endpoint: String
    var modelID: String
    var selectedModelIDs: [String]
    var supportsVision: Bool
    var maxImageBytes: Int?
    var maxRequestBodyBytes: Int?
    var systemPrompt: String?
    var notionEnabled: Bool
    var notionDatabaseID: String?

    init(
        endpoint: String = "https://api.openai.com/v1/chat/completions",
        modelID: String = "gpt-4o-mini",
        selectedModelIDs: [String] = ["gpt-4o-mini"],
        supportsVision: Bool = true,
        maxImageBytes: Int? = nil,
        maxRequestBodyBytes: Int? = nil,
        systemPrompt: String? = nil,
        notionEnabled: Bool = false,
        notionDatabaseID: String? = nil
    ) {
        self.endpoint = endpoint
        self.modelID = modelID
        self.selectedModelIDs = selectedModelIDs
        self.supportsVision = supportsVision
        self.maxImageBytes = maxImageBytes
        self.maxRequestBodyBytes = maxRequestBodyBytes
        self.systemPrompt = systemPrompt
        self.notionEnabled = notionEnabled
        self.notionDatabaseID = notionDatabaseID
    }
}
