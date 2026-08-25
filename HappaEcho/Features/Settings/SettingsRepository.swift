import Foundation

/// Read/write surface for the two provider credentials HappaEcho stores in the
/// Keychain. The SwiftData `AppSettings` model carries only non-sensitive
/// configuration; chat API key and Notion integration token live exclusively
/// behind `CredentialStore`, never in the store.
struct SettingsRepository {
    /// Production account names inside the `com.happaecho.credentials` service.
    /// Tests keep a distance by injecting an in-memory `CredentialStore`, so
    /// these constants stay authoritative without being exercised against the
    /// real Keychain.
    static let chatAPIKeyAccount = "chat-api-key"
    static let notionTokenAccount = "notion-token"

    private let store: CredentialStore

    /// - Parameter store: Backing credential store. Defaults to the Keychain;
    ///   tests inject a namespaced in-memory double.
    init(store: CredentialStore = KeychainService()) {
        self.store = store
    }

    // MARK: - Chat API key

    /// Returns the configured chat API key, or `nil` when none is stored.
    func loadChatAPIKey() throws -> String? {
        try stringValue(for: Self.chatAPIKeyAccount)
    }

    /// Stores the chat API key, replacing any previously stored value.
    func saveChatAPIKey(_ key: String) throws {
        try setStringValue(key, for: Self.chatAPIKeyAccount)
    }

    // MARK: - Notion token

    /// Returns the configured Notion integration token, or `nil` when none is
    /// stored.
    func loadNotionToken() throws -> String? {
        try stringValue(for: Self.notionTokenAccount)
    }

    /// Stores the Notion integration token, replacing any previously stored
    /// value.
    func saveNotionToken(_ token: String) throws {
        try setStringValue(token, for: Self.notionTokenAccount)
    }

    // MARK: - Encoding

    private func stringValue(for account: String) throws -> String? {
        guard let data = try store.data(account: account) else { return nil }
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return string
    }

    private func setStringValue(_ value: String, for account: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        try store.set(data, account: account)
    }
}
