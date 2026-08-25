import XCTest
@testable import HappaEcho

/// In-memory `CredentialStore` double so repository tests never touch the real
/// Keychain. Records the account names read and written so the production
/// credential mapping stays under test.
private final class MemoryCredentialStore: CredentialStore {
    private var storage: [String: Data] = [:]
    private(set) var writtenAccounts: [String] = []
    private(set) var readAccounts: [String] = []

    func set(_ data: Data, account: String) throws {
        storage[account] = data
        writtenAccounts.append(account)
    }

    func data(account: String) throws -> Data? {
        readAccounts.append(account)
        return storage[account]
    }

    func delete(account: String) throws {
        storage[account] = nil
    }
}

final class SettingsRepositoryTests: XCTestCase {
    private var store: MemoryCredentialStore!
    private var repository: SettingsRepository!

    override func setUp() {
        super.setUp()
        store = MemoryCredentialStore()
        repository = SettingsRepository(store: store)
    }

    // MARK: - Missing values

    func testLoadMissingValuesReturnNil() throws {
        XCTAssertNil(try repository.loadChatAPIKey())
        XCTAssertNil(try repository.loadNotionToken())
    }

    // MARK: - Round trips

    func testChatAPIKeyRoundTrips() throws {
        try repository.saveChatAPIKey("sk-test-1234")
        XCTAssertEqual(try repository.loadChatAPIKey(), "sk-test-1234")
    }

    func testNotionTokenRoundTrips() throws {
        try repository.saveNotionToken("ntn_abc123")
        XCTAssertEqual(try repository.loadNotionToken(), "ntn_abc123")
    }

    func testUpdateReplacesPreviousValue() throws {
        try repository.saveChatAPIKey("sk-old")
        try repository.saveChatAPIKey("sk-new")
        XCTAssertEqual(try repository.loadChatAPIKey(), "sk-new")
    }

    func testUTF8RoundTripForValues() throws {
        let key = "sk-你好-键"
        try repository.saveChatAPIKey(key)
        XCTAssertEqual(try repository.loadChatAPIKey(), key)
    }

    // MARK: - Production account mapping

    func testSaveWritesToProductionAccountNames() throws {
        try repository.saveChatAPIKey("sk-test-1234")
        try repository.saveNotionToken("ntn_abc123")
        XCTAssertEqual(store.writtenAccounts, ["chat-api-key", "notion-token"])
    }

    func testChatAPIKeyAndNotionTokenRemainIsolated() throws {
        try repository.saveChatAPIKey("sk-1")
        try repository.saveNotionToken("ntn-1")

        XCTAssertEqual(try repository.loadNotionToken(), "ntn-1")
        XCTAssertEqual(try repository.loadChatAPIKey(), "sk-1")

        XCTAssertEqual(store.writtenAccounts, ["chat-api-key", "notion-token"])
        XCTAssertEqual(store.readAccounts, ["notion-token", "chat-api-key"])
    }

    // MARK: - SwiftData settings must not hold secrets

    func testAppSettingsExposesNoSecretProperties() {
        let settings = AppSettings()
        let propertyNames = Mirror(reflecting: settings).children.compactMap { $0.label }
        let forbiddenTerms = ["key", "token", "secret", "credential", "password"]

        for name in propertyNames {
            let lower = name.lowercased()
            for term in forbiddenTerms where lower.contains(term) {
                XCTFail("AppSettings must never persist a secret in SwiftData, but declares '\(name)'")
            }
        }
    }
}
