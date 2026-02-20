import SwiftUI

/// Sticky input bar at the bottom of ChatView.
///
/// Features:
/// - Multi-line `TextField` that expands up to ~5 lines.
/// - Send button disabled while empty or while a response is loading.
/// - Submits on the Return key (single line mode triggers send; long text uses the button).
struct MessageInputField: View {

    @Binding var text: String
    let isLoading: Bool
    let onSend: () -> Void

    @FocusState private var isFocused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message Sage…", text: $text, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
                .focused($isFocused)
                .onSubmit {
                    if canSend { onSend() }
                }
                .submitLabel(.send)
                .disabled(isLoading)

            sendButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.background)
    }

    private var sendButton: some View {
        Button(action: {
            isFocused = false
            onSend()
        }) {
            Group {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.up")
                        .fontWeight(.semibold)
                }
            }
            .frame(width: 32, height: 32)
            .foregroundStyle(.white)
            .background(canSend ? Color.accentColor : Color(.systemGray3), in: Circle())
        }
        .disabled(!canSend)
        .animation(.easeInOut(duration: 0.15), value: canSend)
    }
}

#Preview {
    VStack {
        Spacer()
        MessageInputField(text: .constant(""), isLoading: false, onSend: {})
        MessageInputField(text: .constant("Hello!"), isLoading: false, onSend: {})
        MessageInputField(text: .constant("Sending…"), isLoading: true, onSend: {})
    }
}
