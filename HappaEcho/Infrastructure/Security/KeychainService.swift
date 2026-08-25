import Foundation
import Security

/// Errors surfaced by the Keychain-backed credential store. Consumers map
/// these to user-facing messages; the raw `OSStatus` is preserved for
/// diagnostics.
enum KeychainError: Error, Equatable {
    /// The Keychain call failed with a status not covered by the other cases.
    case unexpectedStatus(OSStatus)
    /// Stored bytes could not be interpreted as `Data`.
    case invalidData
}

/// Stores opaque credential blobs in the device Keychain.
///
/// All items use the generic-password class under the single service
/// `com.happaecho.credentials`, keyed by account. Callers that must not touch
/// production credentials (tests, scratch workflows) pass namespaced account
/// names.
protocol CredentialStore {
    /// Inserts `data`, or updates the existing item for `account` in place.
    func set(_ data: Data, account: String) throws
    /// Returns the stored bytes for `account`, or `nil` when nothing exists.
    func data(account: String) throws -> Data?
    /// Deletes the item for `account`. Deleting a missing account is a no-op.
    func delete(account: String) throws
}

/// Security.framework-backed `CredentialStore`.
///
/// Items are generic passwords protected by
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: they survive device
/// reboots but never migrate to other devices or leave the protected device.
final class KeychainService: CredentialStore {
    /// Fixed service separating HappaEcho credentials from every other app's
    /// Keychain items. Account names distinguish individual credentials.
    static let service = "com.happaecho.credentials"

    init() {}

    func set(_ data: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]

        // Prefer an in-place update so re-saving a credential never leaves a
        // duplicate item behind.
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecItemNotFound {
            var attributes = query
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(attributes as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
            return
        }
        guard updateStatus == errSecSuccess else {
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    func data(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainError.invalidData
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status == errSecItemNotFound {
            return
        }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
