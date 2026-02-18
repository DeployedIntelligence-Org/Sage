import SwiftUI

/// Root view — shows onboarding for new users, then transitions to the main tab experience.
struct ContentView: View {

    @State private var onboardingComplete: Bool = false
    @State private var showSettings = false

    var body: some View {
        ZStack {
            if onboardingComplete {
                HomeView()
                    .transition(.opacity)
            } else {
                NavigationStack {
                    OnboardingView(onComplete: { onboardingComplete = true })
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
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: onboardingComplete)
    }
}

#Preview {
    ContentView()
}
