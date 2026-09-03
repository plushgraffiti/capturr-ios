/// This service performs the app's low-level reads and writes in the system Keychain.
/// `CredentialsManager` is its only app-level owner and uses it to persist Roam tokens.
/// Values remain available to background sync after the first device unlock, stay tied
/// to this device, and are never stored in SwiftData or user defaults.

import Foundation
import Security
import OSLog

final class KeychainService {
    static let shared = KeychainService()

    private let service = "com.capturr.app"
    private let logger = Logger(category: "Keychain")

    private init() {}

    // MARK: - Key Types

    enum Key {
        case primaryAppendToken
        case primaryBackendToken
        case graphAppendToken(graphId: String)

        var account: String {
            switch self {
            case .primaryAppendToken:
                return "primary.appendToken"
            case .primaryBackendToken:
                return "primary.backendToken"
            case .graphAppendToken(let graphId):
                return "graph.\(graphId).appendToken"
            }
        }
    }

    // MARK: - Errors

    enum KeychainError: Error, LocalizedError {
        case duplicateItem
        case itemNotFound
        case unexpectedStatus(OSStatus)
        case encodingFailed
        case decodingFailed

        var errorDescription: String? {
            switch self {
            case .duplicateItem:
                return "Item already exists in Keychain"
            case .itemNotFound:
                return "Item not found in Keychain"
            case .unexpectedStatus(let status):
                return "Keychain error: \(status)"
            case .encodingFailed:
                return "Failed to encode value for Keychain"
            case .decodingFailed:
                return "Failed to decode value from Keychain"
            }
        }
    }

    // MARK: - Public API

    // Save a string value to the Keychain.
    // Updates existing item if present.
    func save(_ value: String, for key: Key) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.account
        ]

        // Check if item exists
        let status = SecItemCopyMatching(query as CFDictionary, nil)

        if status == errSecSuccess {
            // Update existing item
            let attributesToUpdate: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]

            let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)

            if updateStatus != errSecSuccess {
                logger.error("Keychain update failed: \(updateStatus)")
                throw KeychainError.unexpectedStatus(updateStatus)
            }

            logger.debug("Updated Keychain item: \(key.account)")
        } else if status == errSecItemNotFound {
            // Add new item
            var newItem = query
            newItem[kSecValueData as String] = data
            newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

            let addStatus = SecItemAdd(newItem as CFDictionary, nil)

            if addStatus != errSecSuccess {
                logger.error("Keychain add failed: \(addStatus)")
                throw KeychainError.unexpectedStatus(addStatus)
            }

            logger.debug("Added Keychain item: \(key.account)")
        } else {
            logger.error("Keychain query failed: \(status)")
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // Load a string value from the Keychain.
    // Returns nil if not found.
    func load(for key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var keychainItem: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &keychainItem)

        if status == errSecSuccess, let data = keychainItem as? Data {
            return String(data: data, encoding: .utf8)
        }

        if status != errSecItemNotFound {
            logger.warning("Keychain load failed: \(status)")
        }

        return nil
    }

    // Delete an item from the Keychain.
    func delete(for key: Key) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.account
        ]

        let status = SecItemDelete(query as CFDictionary)

        if status != errSecSuccess && status != errSecItemNotFound {
            logger.error("Keychain delete failed: \(status)")
            throw KeychainError.unexpectedStatus(status)
        }

        logger.debug("Deleted Keychain item: \(key.account)")
    }

    // Check if an item exists in the Keychain without loading its value.
    func exists(for key: Key) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.account,
            kSecReturnData as String: false
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
}
