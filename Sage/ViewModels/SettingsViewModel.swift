import Foundation

/// Manages state and actions for the Settings screen.
@MainActor
final class SettingsViewModel: ObservableObject {

    // MARK: - Published State

    /// The draft key the user is typing — never persisted until Save is tapped.
    @Published var apiKeyDraft: String = ""

    /// True when a valid key is already stored in the Keychain.
    @Published var isKeyStored: Bool = false

    @Published var showSavedConfirmation: Bool = false
    @Published var showError: Bool = false
    @Published var errorMessage: String? = nil

    // MARK: - Init

    init() {
        refreshKeyStatus()
    }

    // MARK: - Actions

    func saveKey() {
        let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            try Secrets.setAnthropicAPIKey(trimmed)
            apiKeyDraft = ""
            refreshKeyStatus()
            showSavedConfirmation = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func deleteKey() {
        Secrets.deleteAnthropicAPIKey()
        apiKeyDraft = ""
        refreshKeyStatus()
    }

    // MARK: - Private

    private func refreshKeyStatus() {
        isKeyStored = (try? Secrets.anthropicAPIKey()) != nil
    }
}
