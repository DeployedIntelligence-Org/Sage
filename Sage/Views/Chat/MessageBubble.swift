import SwiftUI

/// A single chat bubble displaying one message turn.
///
/// User messages are right-aligned with a tinted background;
/// assistant messages are left-aligned with a secondary fill and markdown rendering.
///
/// Long-pressing any bubble reveals a context menu with Copy, Share, and Delete actions.
/// The last assistant message also offers a Regenerate action.
/// Failed user messages show an inline retry prompt.
struct MessageBubble: View {

    let message: Message
    var isFailed: Bool = false
    var onDelete: () -> Void = {}
    var onRetry: () -> Void = {}

    private var isUser: Bool { message.role.isUser }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 8) {
                if isUser { Spacer(minLength: 48) }

                if !isUser {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.tint)
                        .frame(width: 24, height: 24)
                        .background(.tint.opacity(0.12), in: Circle())
                        .padding(.bottom, 2)
                }

                bubbleContent
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(bubbleColor, in: bubbleShape)
                    .contextMenu { contextMenuItems }

                if !isUser { Spacer(minLength: 48) }
            }

            if isFailed {
                failedRow
                    .padding(.trailing, 4)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Bubble content

    @ViewBuilder
    private var bubbleContent: some View {
        if isUser {
            Text(message.content)
                .font(.body)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            MarkdownTextView(text: message.content)
                .foregroundStyle(Color.primary)
        }
    }

    // MARK: - Failed row

    private var failedRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
            Text("Failed to send")
                .font(.caption2)
                .foregroundStyle(.red)
            Button("Retry", action: onRetry)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tint)
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private var contextMenuItems: some View {
        Button {
            UIPasteboard.general.string = message.content
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }

        ShareLink(item: message.content) {
            Label("Share", systemImage: "square.and.arrow.up")
        }

        Divider()

        Button(role: .destructive, action: onDelete) {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Helpers

    private var bubbleShape: some Shape {
        UnevenRoundedRectangle(
            topLeadingRadius: isUser ? 18 : 4,
            bottomLeadingRadius: 18,
            bottomTrailingRadius: isUser ? 4 : 18,
            topTrailingRadius: 18
        )
    }

    private var bubbleColor: Color {
        isUser ? .accentColor : Color(.secondarySystemBackground)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 12) {
            MessageBubble(
                message: Message(
                    conversationId: 1,
                    role: .user,
                    content: "How can I improve my scales?"
                )
            )
            MessageBubble(
                message: Message(
                    conversationId: 1,
                    role: .assistant,
                    content: """
                    Great question! Here's a **structured practice plan**:

                    1. Start at **60 bpm** hands separately
                    2. Focus on *evenness* between fingers
                    3. Once comfortable, try hands together

                    ```swift
                    // Example metronome logic
                    let bpm = 60
                    let interval = 60.0 / Double(bpm)
                    ```

                    - Bump tempo by 5 bpm each day
                    - Record yourself to track progress
                    """
                ),
            )
            MessageBubble(
                message: Message(
                    conversationId: 1,
                    role: .user,
                    content: "Thanks, I'll try that tonight."
                ),
                isFailed: true
            )
        }
        .padding(.vertical)
    }
}
