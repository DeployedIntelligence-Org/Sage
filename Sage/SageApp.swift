import SwiftUI

@main
struct SageApp: App {

    init() {
        openDatabase()
        seedAPIKeyFromConfig()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }

    // MARK: - Private

    private func openDatabase() {
        do {
            try DatabaseService.shared.open()
        } catch {
            // In production this would surface a user-facing error.
            // For now we log and let the app degrade gracefully.
            print("[SageApp] Failed to open database: \(error.localizedDescription)")
        }
    }

    /// Seeds the Keychain with the API key baked in via LocalConfig.xcconfig → Info.plist.
    /// Only activates when the value starts with "sk-ant-" (i.e. a real key is present).
    /// Does not overwrite a key the user has already saved manually via Settings.
    /// Safe to ship — the placeholder string is never a valid Anthropic key.
    private func seedAPIKeyFromConfig() {
        guard
            let key = Bundle.main.object(forInfoDictionaryKey: "AnthropicAPIKey") as? String,
            key.hasPrefix("sk-ant-")
        else { return }

        // Don't clobber a key the user set themselves.
        if (try? Secrets.anthropicAPIKey()) != nil { return }

        try? Secrets.setAnthropicAPIKey(key)
        print("[SageApp] API key seeded from LocalConfig.xcconfig")
    }
}
