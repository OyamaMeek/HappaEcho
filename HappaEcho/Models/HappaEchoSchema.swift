import Foundation
import SwiftData

/// Central schema definition for the HappaEcho store.
enum HappaEchoSchema {
    /// All persisted model types, in declaration order.
    static let allModels: [any PersistentModel.Type] = [
        Conversation.self,
        Message.self,
        MessageAttachment.self,
        NotionPageBinding.self,
        AppSettings.self,
    ]

    /// Builds a container over every model type. Pass `inMemory: true` for tests.
    static func makeContainer(inMemory: Bool) throws -> ModelContainer {
        let schema = Schema(allModels)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
