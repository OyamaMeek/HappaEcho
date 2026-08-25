import XCTest
@testable import HappaEcho

/// Exercises the real Security.framework Keychain wrapper. Every test writes
/// under a unique, randomly-namespaced account (`test.<uuid>`) so a failure or
/// leftover item never collides with the production credential accounts
/// (`chat-api-key`, `notion-token`) used by `SettingsRepository`.
final class KeychainServiceTests: XCTestCase {
    private var service: KeychainService!
    private var account: String!

    override func setUp() {
        super.setUp()
        service = KeychainService()
        account = "test.\(UUID().uuidString)"
    }

    override func tearDown() {
        try? service?.delete(account: account)
        service = nil
        account = nil
        super.tearDown()
    }

    func testReadingMissingAccountReturnsNil() throws {
        XCTAssertNil(try service.data(account: account))
    }

    func testSetThenReadReturnsStoredData() throws {
        let payload = Data("hello".utf8)
        try service.set(payload, account: account)
        XCTAssertEqual(try service.data(account: account), payload)
    }

    func testSetTwiceUpdatesExistingItemInPlace() throws {
        try service.set(Data("first".utf8), account: account)
        try service.set(Data("second".utf8), account: account)
        XCTAssertEqual(try service.data(account: account), Data("second".utf8))
    }

    func testDeleteRemovesItem() throws {
        try service.set(Data("gone".utf8), account: account)
        try service.delete(account: account)
        XCTAssertNil(try service.data(account: account))
    }

    func testDeletingMissingAccountIsNotAnError() throws {
        XCTAssertNoThrow(try service.delete(account: account))
    }

    func testStoresDistinctValuesUnderDistinctAccounts() throws {
        try service.set(Data("one".utf8), account: account)
        let other = "test.\(UUID().uuidString)"
        defer { try? service.delete(account: other) }
        try service.set(Data("two".utf8), account: other)

        XCTAssertEqual(try service.data(account: account), Data("one".utf8))
        XCTAssertEqual(try service.data(account: other), Data("two".utf8))
    }

    func testUTF8RoundTrip() throws {
        let message = "你好，HappaEcho！🎉"
        try service.set(Data(message.utf8), account: account)
        let read = try XCTUnwrap(try service.data(account: account))
        XCTAssertEqual(String(data: read, encoding: .utf8), message)
    }
}
