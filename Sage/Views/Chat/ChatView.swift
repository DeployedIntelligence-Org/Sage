import SwiftUI

/// Main chat interface — a scrollable list of message bubbles with a sticky input bar.
///
/// Automatically:
/// - Loads (or creates) a conversation on first appear.
/// - Scrolls to the newest message after each send.
/// - Avoids the keyboard via the system's default safe-area inset handling.
struct ChatView: View {

    @StateObject private var viewModel: ChatViewModel
    @State private var showConversationList = false

    init(skillGoal: SkillGoal) {
        _viewModel = StateObject(wrappedValue: ChatViewModel(skillGoal: skillGoal))
    }

    var body: some View {
        VStack(spacing: 0) {
            messageList
            Divider()
            MessageInputField(
                text: $viewModel.inputText,
                isLoading: viewModel.isLoading,
                onSend: {
                    Task { await viewModel.sendMessage() }
                }
            )
        }
        .navigationTitle("Coach")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showConversationList = true
                } label: {
                    Image(systemName: "bubble.left.and.bubble.right")
                }
            }
        }
        .sheet(isPresented: $showConversationList) {
            ConversationListView(viewModel: viewModel, isPresented: $showConversationList)
        }
        .task { await viewModel.loadConversation() }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Message list

    @ViewBuilder
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if viewModel.messages.isEmpty && !viewModel.isLoading {
                        emptyState
                            .padding(.top, 60)
                    }

                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }

                    // Show the animated dots only while waiting for the first streaming chunk.
                    // Once the assistant bubble has content it renders in-line, so we hide this.
                    if viewModel.isLoading && (viewModel.messages.last?.role != .assistant || viewModel.messages.last?.content.isEmpty == true) {
                        typingIndicator
                            .id("typing")
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .onChange(of: viewModel.messages.count) {
                scrollToBottom(proxy: proxy)
            }
            // Keep the view scrolled to the bottom as streaming chunks grow the last bubble.
            .onChange(of: viewModel.messages.last?.content) {
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.isLoading) {
                if viewModel.isLoading {
                    withAnimation { proxy.scrollTo("typing", anchor: .bottom) }
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("Your AI Coach")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Ask anything about your practice,\nget personalised tips, or share your progress.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Typing indicator

    private var typingIndicator: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.caption)
                .foregroundStyle(.tint)
                .frame(width: 24, height: 24)
                .background(.tint.opacity(0.12), in: Circle())

            TypingDots()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    Color(.secondarySystemBackground),
                    in: UnevenRoundedRectangle(
                        topLeadingRadius: 4,
                        bottomLeadingRadius: 18,
                        bottomTrailingRadius: 18,
                        topTrailingRadius: 18
                    )
                )

            Spacer(minLength: 48)
        }
    }

    // MARK: - Helpers

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let lastId = viewModel.messages.last?.id else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(lastId, anchor: .bottom)
        }
    }
}

// MARK: - Typing animation

/// Three animated dots indicating the assistant is composing a reply.
private struct TypingDots: View {

    @State private var phase = 0

    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .frame(width: 7, height: 7)
                    .foregroundStyle(.secondary)
                    .scaleEffect(phase == index ? 1.3 : 0.9)
                    .animation(.easeInOut(duration: 0.3), value: phase)
            }
        }
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ChatView(skillGoal: SkillGoal(
            id: 1,
            skillName: "Piano",
            currentLevel: "Beginner",
            targetLevel: "Intermediate",
            customMetrics: [
                CustomMetric(name: "Scales per minute", unit: "spm", isHigherBetter: true)
            ]
        ))
    }
}
