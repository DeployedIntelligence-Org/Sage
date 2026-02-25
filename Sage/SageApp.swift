import SwiftUI

@main
struct SageApp: App {

    init() {
        // Handle UI testing reset
        if CommandLine.arguments.contains("--reset-for-testing") {
            resetAppStateForTesting()
        }
        
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

    private func resetAppStateForTesting() {
        // Clear the database to ensure onboarding shows
        do {
            try DatabaseService.shared.open()
            let skills = try DatabaseService.shared.fetchAll()
            for skill in skills {
                if let skillId = skill.id {
                    try DatabaseService.shared.delete(id: skillId)
                }
            }
        } catch {
            print("[SageApp] Failed to reset database for testing: \(error)")
        }
    }

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
