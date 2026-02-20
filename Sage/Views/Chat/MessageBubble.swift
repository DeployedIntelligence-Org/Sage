import SwiftUI

/// A single chat bubble displaying one message turn.
///
/// User messages are right-aligned with a tinted background;
/// assistant messages are left-aligned with a secondary fill.
struct MessageBubble: View {

    let message: Message

    private var isUser: Bool { message.role.isUser }

    var body: some View {
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

            Text(message.content)
                .font(.body)
                .foregroundStyle(isUser ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(bubbleColor, in: bubbleShape)
                .fixedSize(horizontal: false, vertical: true)

            if !isUser { Spacer(minLength: 48) }
        }
        .padding(.horizontal, 16)
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
    VStack(spacing: 12) {
        MessageBubble(message: Message(
            conversationId: 1,
            role: .user,
            content: "How can I improve my scales?"
        ))
        MessageBubble(message: Message(
            conversationId: 1,
            role: .assistant,
            content: "Great question! Start by practicing hands separately at 60 bpm, focusing on evenness. Once comfortable, try hands together and bump the tempo by 5 bpm every day."
        ))
    }
    .padding(.vertical)
}
