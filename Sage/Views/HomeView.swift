import SwiftUI

/// Root tab container shown after onboarding is complete.
struct HomeView: View {

    @State private var skillGoal: SkillGoal? = nil

    var body: some View {
        TabView {
            NavigationStack {
                placeholderTab(
                    icon: "figure.run",
                    title: "Practice",
                    description: "Track your practice sessions and log progress."
                )
                .navigationTitle("Practice")
            }
            .tabItem { Label("Practice", systemImage: "figure.run") }

            NavigationStack {
                chatTab
            }
            .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }

            NavigationStack {
                placeholderTab(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Insights",
                    description: "See patterns and weekly summaries of your progress."
                )
                .navigationTitle("Insights")
            }
            .tabItem { Label("Insights", systemImage: "chart.line.uptrend.xyaxis") }
        }
        .task { loadSkillGoal() }
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
