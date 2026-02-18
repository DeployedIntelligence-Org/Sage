import Foundation

/// Thin façade over `KeychainService` for secret management.
///
/// Usage:
/// ```swift
/// // Store during onboarding or Settings:
/// try Secrets.setAnthropicAPIKey("sk-ant-...")
///
/// // Read before making API calls (done internally by ClaudeService):
/// let key = try Secrets.anthropicAPIKey()
/// ```
enum Secrets {

    /// Stores the Anthropic API key securely in the Keychain.
    static func setAnthropicAPIKey(_ key: String) throws {
        try KeychainService.shared.set(key, for: .anthropicAPIKey)
    }

    /// Returns the stored Anthropic API key, or `nil` if not set.
    static func anthropicAPIKey() throws -> String? {
        try KeychainService.shared.get(.anthropicAPIKey)
    }

    /// Removes the stored Anthropic API key from the Keychain.
    @discardableResult
    static func deleteAnthropicAPIKey() -> Bool {
        KeychainService.shared.delete(.anthropicAPIKey)
    }
}
