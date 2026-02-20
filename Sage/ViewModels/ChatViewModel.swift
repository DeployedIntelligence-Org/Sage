import Foundation

/// Drives the Chat tab.
///
/// Responsibilities:
/// - Load or create a `Conversation` for the active `SkillGoal`.
/// - Persist and expose `Message` rows.
/// - Forward the full conversation history to `ClaudeService` on each send.
@MainActor
final class ChatViewModel: ObservableObject {

    // MARK: - Published state

    @Published var messages: [Message] = []
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    // MARK: - Private state

    private var conversation: Conversation?
    private let skillGoal: SkillGoal
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

    /// Call once when the view appears. Loads the most recent conversation (or creates one).
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

            conversation = convs[0]
            guard let convId = conversation?.id else { return }
            messages = try db.fetchMessages(conversationId: convId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Actions

    /// Sends the current `inputText` to Claude and appends both the user and assistant messages.
    func sendMessage() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }
        guard let convId = conversation?.id else { return }

        inputText = ""
        errorMessage = nil

        // Append & persist user message immediately for instant UI feedback.
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

        do {
            let systemPrompt = PromptTemplates.coachSystem(
                skillName: skillGoal.skillName,
                currentLevel: skillGoal.currentLevel,
                targetLevel: skillGoal.targetLevel,
                metrics: skillGoal.customMetrics
            )

            let response = try await claude.sendConversation(
                messages: messages,
                systemPrompt: systemPrompt
            )

            let replyText = response.text

            var assistantMsg = Message(
                conversationId: convId,
                role: .assistant,
                content: replyText
            )
            assistantMsg = try db.insert(assistantMsg)
            messages.append(assistantMsg)
        } catch {
            errorMessage = friendlyError(error)
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
