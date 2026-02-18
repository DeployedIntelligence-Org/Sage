import SwiftUI

/// Root view — presents the onboarding flow for now.
/// Will be replaced with tab bar navigation once onboarding is complete.
struct ContentView: View {

    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            OnboardingView()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .accessibilityLabel("Settings")
                        }
                    }
                }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}

#Preview {
    ContentView()
}
