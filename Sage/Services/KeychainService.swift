import Foundation
import Security

// MARK: - Protocol

/// Abstraction over Keychain access, enabling dependency injection in tests.
protocol KeychainStoring {
    func set(_ value: String, for key: KeychainService.Key) throws
    func get(_ key: KeychainService.Key) throws -> String?
    @discardableResult func delete(_ key: KeychainService.Key) -> Bool
}

// MARK: - Implementation

/// Provides secure storage and retrieval of sensitive values using the iOS Keychain.
///
/// All keys are namespaced under a bundle-ID prefix to avoid collisions with
/// other apps on the same device.
final class KeychainService: KeychainStoring {

    // MARK: - Singleton

    static let shared = KeychainService()

    // MARK: - Keys

    enum Key: String {
        case anthropicAPIKey = "anthropic_api_key"
    }

    // MARK: - Private

    private let service: String

    init(service: String = Bundle.main.bundleIdentifier ?? "com.sage.app") {
        self.service = service
    }

    // MARK: - Public API

    /// Stores a string value in the Keychain.
    /// - Parameters:
    ///   - value: The plaintext string to store.
    ///   - key: The Keychain key.
    /// - Throws: `KeychainError` if the operation fails.
    func set(_ value: String, for key: Key) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // Delete any existing item first to allow updating.
        delete(key)

        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      key.rawValue,
            kSecValueData:        data,
            kSecAttrAccessible:   kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    /// Retrieves a string value from the Keychain.
    /// - Parameter key: The Keychain key.
    /// - Returns: The stored string, or `nil` if not found.
    /// - Throws: `KeychainError` if reading fails for any reason other than item not found.
    func get(_ key: Key) throws -> String? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      key.rawValue,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let string = String(data: data, encoding: .utf8) else {
                throw KeychainError.decodingFailed
            }
            return string
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.readFailed(status)
        }
    }

    /// Removes a value from the Keychain.
    /// - Parameter key: The Keychain key to delete.
    @discardableResult
    func delete(_ key: Key) -> Bool {
        let query: [CFString: Any] = [
            kSecClass:        kSecClassGenericPassword,
            kSecAttrService:  service,
            kSecAttrAccount:  key.rawValue
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

// MARK: - KeychainError

enum KeychainError: Error, LocalizedError {
    case encodingFailed
    case decodingFailed
    case saveFailed(OSStatus)
    case readFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:        return "Failed to encode value for Keychain storage."
        case .decodingFailed:        return "Failed to decode value retrieved from Keychain."
        case .saveFailed(let s):     return "Keychain save failed with status \(s)."
        case .readFailed(let s):     return "Keychain read failed with status \(s)."
        }
    }
}
