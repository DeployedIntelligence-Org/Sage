import SwiftUI

@main
struct SageApp: App {

    init() {
        openDatabase()
        seedAPIKeyFromConfig()
        // Enable verbose streaming logs during debugging.
        #if DEBUG
        ClaudeService.shared.setStreamingLoggingEnabled(false)
        #endif
        // Register NotificationService as UNUserNotificationCenterDelegate before
        // the app finishes launching so cold-start notification taps are handled.
        _ = NotificationService.shared
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
            print("[SageApp] Failed to open database: \(error.localizedDescription)")
        }
    }

    private func seedAPIKeyFromConfig() {
        guard
            let key = Bundle.main.object(forInfoDictionaryKey: "AnthropicAPIKey") as? String,
            key.hasPrefix("sk-ant-")
        else { return }
        if (try? Secrets.anthropicAPIKey()) != nil { return }
        try? Secrets.setAnthropicAPIKey(key)
        print("[SageApp] API key seeded from LocalConfig.xcconfig")
    }
}
