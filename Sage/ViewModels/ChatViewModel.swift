import Foundation

/// Drives the Chat tab.
///
/// Responsibilities:
/// - Load or create a `Conversation` for the active `SkillGoal`.
/// - Persist and expose `Message` rows.
/// - Forward the full conversation history to `ClaudeService` on each send.
/// - Manage a list of all conversations: select, create new, and delete.
/// - Auto-generate a title for each conversation after the first assistant reply.
@MainActor
final class ChatViewModel: ObservableObject {

    // MARK: - Published state

    @Published var messages: [Message] = []
    @Published var conversations: [Conversation] = []
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    /// The ID of the user message that most recently failed to send.
    @Published var failedUserMessageId: Int64? = nil

    // MARK: - Private state

    private(set) var conversation: Conversation?
    private let skillGoal: SkillGoal

    /// The ID of the currently active conversation, for highlighting in `ConversationListView`.
    var activeConversationId: Int64? { conversation?.id }
    private let db: DatabaseService
    private let claude: ClaudeService

    // MARK: - Init

    init(
        skillGoal: SkillGoal,
        db: DatabaseService = .shared,
        claude: ClaudeService = .shared
    ) {
        self.skillGoal = skillGoal
        self.db = db
        self.claude = claude
    }

    // MARK: - Lifecycle

    /// Call once when the view appears. Loads all conversations and opens the most recent one
    /// (or creates one if none exist yet).
    func loadConversation() async {
        do {
            guard let goalId = skillGoal.id else { return }
            var convs = try db.fetchConversations(skillGoalId: goalId)

            if convs.isEmpty {
                let newConv = try db.insert(
                    Conversation(skillGoalId: goalId, title: nil)
                )
                convs = [newConv]
            }

            conversations = convs
            try await selectConversation(convs[0])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Conversation management

    /// Switches the active conversation and loads its messages.
    func selectConversation(_ conv: Conversation) async throws {
        conversation = conv
        guard let convId = conv.id else { return }
        messages = try db.fetchMessages(conversationId: convId)
    }

    /// Creates a new blank conversation and makes it the active one.
    func newConversation() async {
        do {
            guard let goalId = skillGoal.id else { return }
            let newConv = try db.insert(Conversation(skillGoalId: goalId, title: nil))
            conversations.insert(newConv, at: 0)
            try await selectConversation(newConv)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Deletes a conversation (and its messages via cascade) and updates the list.
    /// If the deleted conversation is currently active, switches to the next available one
    /// (or creates a fresh conversation if none remain).
    func deleteConversation(_ conv: Conversation) async {
        do {
            guard let convId = conv.id else { return }
            try db.deleteConversation(id: convId)
            conversations.removeAll { $0.id == convId }

            // If we just deleted the active conversation, switch to another one.
            if conversation?.id == convId {
                if let next = conversations.first {
                    try await selectConversation(next)
                } else {
                    await newConversation()
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Actions

    /// Sends the current `inputText` to Claude using SSE streaming.
    ///
    /// The assistant reply appears token-by-token: a placeholder `Message` is inserted
    /// immediately and its `content` is grown in place as chunks arrive.
    func sendMessage() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }
        guard let convId = conversation?.id else { return }

        inputText = ""
        errorMessage = nil
        failedUserMessageId = nil

        // 1. Persist & show the user message immediately for instant UI feedback.
        var userMsg = Message(conversationId: convId, role: .user, content: text)
        do {
            userMsg = try db.insert(userMsg)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        messages.append(userMsg)

        isLoading = true
        defer { isLoading = false }

        // 2. Stream assistant reply (inserts placeholder, streams, persists, auto-titles).
        await streamAssistantReply(convId: convId, failedUserMsgId: userMsg.id)
    }

    // MARK: - Message actions

    /// Deletes a message from the database and removes it from the in-memory list.
    func deleteMessage(_ message: Message) async {
        guard let id = message.id else { return }
        do {
            try db.deleteMessage(id: id)
            messages.removeAll { $0.id == id }
            if failedUserMessageId == id { failedUserMessageId = nil }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Removes the last assistant message and re-streams a fresh response from Claude.
    func regenerateResponse() async {
        guard !isLoading else { return }
        guard let convId = conversation?.id else { return }

        // Remove the last assistant message if present.
        if messages.last?.role == .assistant {
            let last = messages.removeLast()
            if let id = last.id { try? db.deleteMessage(id: id) }
        }

        guard !messages.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        await streamAssistantReply(convId: convId)
    }

    /// Retries sending after a failure. Clears the failed state and re-streams a response
    /// for the existing user message (which was already persisted).
    func retryLastFailedMessage() async {
        guard !isLoading, let convId = conversation?.id else { return }
        failedUserMessageId = nil
        errorMessage = nil

        isLoading = true
        defer { isLoading = false }

        await streamAssistantReply(convId: convId)
    }

    /// Inserts an empty assistant placeholder and streams a reply from Claude using the
    /// current messages list. Shared by `sendMessage`, `regenerateResponse`, and `retryLastFailedMessage`.
    /// Pass `failedUserMsgId` to mark the originating user message as failed on error.
    private func streamAssistantReply(convId: Int64, failedUserMsgId: Int64? = nil) async {
        var assistantMsg = Message(conversationId: convId, role: .assistant, content: "")
        do {
            assistantMsg = try db.insert(assistantMsg)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        messages.append(assistantMsg)

        do {
            let systemPrompt = PromptTemplates.coachSystem(
                skillName: skillGoal.skillName,
                currentLevel: skillGoal.currentLevel,
                targetLevel: skillGoal.targetLevel,
                metrics: skillGoal.customMetrics
            )

            let historyForStream = messages.dropLast() // exclude the empty placeholder
            let stream = claude.streamConversation(
                messages: Array(historyForStream),
                systemPrompt: systemPrompt
            )

            for try await chunk in stream {
                if let lastIndex = messages.indices.last {
                    messages[lastIndex].content += chunk
                }
            }

            if let lastIndex = messages.indices.last {
                try db.updateMessageContent(messages[lastIndex])
            }

            if conversation?.title == nil, let firstUser = messages.first(where: { $0.role.isUser }) {
                // Fire-and-forget: title generation must not hold isLoading true.
                Task { await self.generateTitle(for: convId, firstUserMessage: firstUser.content) }
            }
        } catch {
            if messages.last?.role == .assistant {
                let partial = messages.removeLast()
                if let id = partial.id { try? db.deleteMessage(id: id) }
            }
            failedUserMessageId = failedUserMsgId
            errorMessage = friendlyError(error)
        }
    }

    // MARK: - Auto-title

    /// Asks Claude to generate a short title for the conversation based on the first user message,
    /// then persists it and refreshes the `conversations` list.
    private func generateTitle(for convId: Int64, firstUserMessage: String) async {
        let titlePrompt = PromptTemplates.conversationTitleUser(firstMessage: firstUserMessage)

        guard let response = try? await claude.send(
            userMessage: titlePrompt,
            systemPrompt: PromptTemplates.conversationTitleSystem,
            maxTokens: 30
        ) else { return }

        let raw = response.text

        // Trim punctuation, quotes, and excess whitespace.
        let title = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            .prefix(80)
            .description

        guard !title.isEmpty else { return }

        guard var conv = conversation, conv.id == convId else { return }
        conv.title = title
        try? db.updateConversationTitle(conv)

        // Reflect updated title in both the active conversation and the list.
        conversation = conv
        if let idx = conversations.firstIndex(where: { $0.id == convId }) {
            conversations[idx] = conv
        }
    }

    // MARK: - Helpers

    private func friendlyError(_ error: Error) -> String {
        if let netErr = error as? NetworkError {
            switch netErr {
            case .missingAPIKey:
                return "No API key found. Add one in Settings."
            case .invalidAPIKey:
                return "Invalid API key. Check your key in Settings."
            case .rateLimited:
                return "Too many requests. Please wait a moment and try again."
            case .noConnection:
                return "No internet connection."
            case .timeout:
                return "Request timed out. Please try again."
            default:
                return "Something went wrong. Please try again."
            }
        }
        return error.localizedDescription
    }
}
