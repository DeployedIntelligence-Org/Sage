import SwiftUI

/// A slide-out list of conversations for a skill goal.
///
/// Displays each conversation's title (or a placeholder if untitled), its timestamp,
/// and an indicator when it's the currently selected conversation.
///
/// Features:
/// - Tap to select a conversation.
/// - Swipe-to-delete with a confirmation destructive action.
/// - "New Chat" button to create a blank conversation.
struct ConversationListView: View {

    @ObservedObject var viewModel: ChatViewModel
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.conversations) { conversation in
                    ConversationRow(conversation: conversation, activeConversationId: viewModel.activeConversationId)
                        .onTapGesture {
                            Task {
                                try? await viewModel.selectConversation(conversation)
                                isPresented = false
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task { await viewModel.deleteConversation(conversation) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Conversations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { isPresented = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await viewModel.newConversation()
                            isPresented = false
                        }
                    } label: {
                        Label("New Chat", systemImage: "square.and.pencil")
                    }
                }
            }
        }
    }
}

// MARK: - Conversation Row

private struct ConversationRow: View {
    let conversation: Conversation
    let activeConversationId: Int64?

    private var isActive: Bool {
        activeConversationId == conversation.id
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.subheadline)
                .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.title ?? "New Conversation")
                    .font(.subheadline)
                    .fontWeight(isActive ? .semibold : .regular)
                    .lineLimit(1)
                Text(conversation.updatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isActive {
                Image(systemName: "checkmark")
                    .font(.caption)
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var isPresented = true
    let goal = SkillGoal(id: 1, skillName: "Piano")
    let vm   = ChatViewModel(skillGoal: goal)
    return ConversationListView(viewModel: vm, isPresented: $isPresented)
}
