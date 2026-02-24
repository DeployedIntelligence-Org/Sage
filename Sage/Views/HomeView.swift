import SwiftUI

/// Root tab container shown after onboarding is complete.
///
/// Observes `NotificationService.shared.recentlyLoggedSessionId`:
/// when a session is quick-logged from the notification banner the app
/// automatically switches to the Chat tab so the user can debrief with Sage.
struct HomeView: View {

    // Tab indices — keep in sync with the TabView content order below.
    private enum Tab: Int {
        case practice = 0
        case schedule = 1
        case chat     = 2
        case insights = 3
    }

    @State private var selectedTab: Int = Tab.practice.rawValue
    @State private var skillGoal: SkillGoal? = nil

    @ObservedObject private var notificationService = NotificationService.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                placeholderTab(
                    icon: "figure.run",
                    title: "Practice",
                    description: "Track your practice sessions and log progress."
                )
                .navigationTitle("Practice")
            }
            .tabItem { Label("Practice", systemImage: "figure.run") }
            .tag(Tab.practice.rawValue)

            NavigationStack {
                CalendarView()
            }
            .tabItem { Label("Schedule", systemImage: "calendar") }
            .tag(Tab.schedule.rawValue)

            NavigationStack {
                chatTab
            }
            .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
            .tag(Tab.chat.rawValue)

            NavigationStack {
                placeholderTab(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Insights",
                    description: "See patterns and weekly summaries of your progress."
                )
                .navigationTitle("Insights")
            }
            .tabItem { Label("Insights", systemImage: "chart.line.uptrend.xyaxis") }
            .tag(Tab.insights.rawValue)
        }
        .task { loadSkillGoal() }
        // After a quick-star rating from the notification, jump to Chat so Sage can follow up.
        .onChange(of: notificationService.recentlyLoggedSessionId) { _, sessionId in
            guard sessionId != nil else { return }
            withAnimation { selectedTab = Tab.chat.rawValue }
            // Consume the signal so repeated changes don't re-fire.
            notificationService.recentlyLoggedSessionId = nil
        }
    }

    // MARK: - Chat tab

    @ViewBuilder
    private var chatTab: some View {
        if let goal = skillGoal {
            ChatView(skillGoal: goal)
        } else {
            placeholderTab(
                icon: "bubble.left.and.bubble.right",
                title: "Chat",
                description: "Get coaching and feedback from Sage."
            )
            .navigationTitle("Chat")
        }
    }

    // MARK: - Helpers

    private func loadSkillGoal() {
        skillGoal = try? DatabaseService.shared.fetchAll().first
    }

    private func placeholderTab(icon: String, title: String, description: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 52))
                .foregroundStyle(Color(.systemGray3))
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }
}

#Preview {
    HomeView()
}
