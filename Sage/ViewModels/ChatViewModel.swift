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

    // MARK: - Logging

    nonisolated private static func log(_ message: String) {
        // Always-on for now; could be toggled via a flag if desired.
        print("[ChatViewModel] \(message)")
    }

    // MARK: - Init

    init(
        skillGoal: SkillGoal,
        db: DatabaseService = .shared,
        claude: ClaudeService = .shared
    ) {
        self.skillGoal = skillGoal
        self.db = db
        self.claude = claude
        Self.log("init \(Unmanaged.passUnretained(self).toOpaque())")
    }

    deinit {
        Self.log("deinit \(Unmanaged.passUnretained(self).toOpaque())")
    }

    // MARK: - Lifecycle

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

    func selectConversation(_ conv: Conversation) async throws {
        conversation = conv
        guard let convId = conv.id else { return }
        messages = try db.fetchMessages(conversationId: convId)
    }

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

    func deleteConversation(_ conv: Conversation) async {
        do {
            guard let convId = conv.id else { return }
            try db.deleteConversation(id: convId)
            conversations.removeAll { $0.id == convId }

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

    func sendMessage() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }
        guard let convId = conversation?.id else { return }

        inputText = ""
        errorMessage = nil
        failedUserMessageId = nil

        // 1. Persist & show the user message immediately.
        var userMsg = Message(conversationId: convId, role: .user, content: text)
        do {
            userMsg = try db.insert(userMsg)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        messages.append(userMsg)

        isLoading = true

        Self.log("sendMessage BEFORE await streamAssistantReply (vm=\(Unmanaged.passUnretained(self).toOpaque()))")
        await streamAssistantReply(convId: convId, failedUserMsgId: userMsg.id)
        Self.log("sendMessage AFTER await streamAssistantReply (vm=\(Unmanaged.passUnretained(self).toOpaque()))")

        isLoading = false
        Self.log("sendMessage finished. isLoading=false (vm=\(Unmanaged.passUnretained(self).toOpaque()))")
    }

    // MARK: - Message actions

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

    func retryLastFailedMessage() async {
        guard !isLoading, let convId = conversation?.id else { return }
        failedUserMessageId = nil
        errorMessage = nil

        isLoading = true
        await streamAssistantReply(convId: convId)
        isLoading = false
        Self.log("retry finished. isLoading=false")
    }

    // MARK: - Streaming

    private func streamAssistantReply(convId: Int64, failedUserMsgId: Int64? = nil) async {
        Self.log("streamAssistantReply ENTER convId=\(convId) (vm=\(Unmanaged.passUnretained(self).toOpaque()))")
        var assistantMsg = Message(conversationId: convId, role: .assistant, content: "")
        do {
            assistantMsg = try db.insert(assistantMsg)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        messages.append(assistantMsg)

        do {
            // Load recent sessions so Claude has full context about recent practice.
            let recentSessions: [PracticeSession]
            if let goalId = skillGoal.id {
                recentSessions = (try? db.fetchPracticeSessions(skillGoalId: goalId)) ?? []
            } else {
                recentSessions = []
            }

            let systemPrompt = PromptTemplates.coachSystem(
                skillName: skillGoal.skillName,
                currentLevel: skillGoal.currentLevel,
                targetLevel: skillGoal.targetLevel,
                metrics: skillGoal.customMetrics,
                recentSessions: recentSessions
            )

            let historyForStream = messages.dropLast() // exclude placeholder
            let stream = claude.streamConversation(
                messages: Array(historyForStream),
                systemPrompt: systemPrompt
            )

            var chunkCount = 0
            var accumulatedText = ""
            let baseUpdateEvery = 3 // Base: update every 3 chunks
            var chunksUntilUpdate = baseUpdateEvery
            
            do {
                for try await chunk in stream {
                    chunkCount += 1
                    
                    // Filter out empty sentinel chunks
                    guard !chunk.isEmpty else { continue }
                    
                    accumulatedText += chunk
                    chunksUntilUpdate -= 1
                    
                    // Check if we should update
                    if chunksUntilUpdate <= 0 {
                        // Check for incomplete markdown syntax
                        let hasIncompleteMarkdown = accumulatedText.hasSuffix("*") || 
                                                   accumulatedText.hasSuffix("**") ||
                                                   accumulatedText.hasSuffix("`") ||
                                                   accumulatedText.hasSuffix("_")
                        
                        if hasIncompleteMarkdown && chunksUntilUpdate > -7 {
                            // Wait 1 more chunk (up to 7 extra chunks max)
                            chunksUntilUpdate = -1
                        } else {
                            // Update now
                            if let lastIndex = self.messages.indices.last {
                                self.messages[lastIndex].content += accumulatedText
                            }
                            accumulatedText = ""
                            chunksUntilUpdate = baseUpdateEvery
                        }
                    }
                }
                
                // Flush any remaining accumulated text
                if !accumulatedText.isEmpty, let lastIndex = self.messages.indices.last {
                    self.messages[lastIndex].content += accumulatedText
                }
            } catch {
                throw error
            }

            Self.log("Streaming finished normally")

            if let lastIndex = messages.indices.last {
                try db.updateMessageContent(messages[lastIndex])
            }

            if conversation?.title == nil, let firstUser = messages.first(where: { $0.role.isUser }) {
                Task { await self.generateTitle(for: convId, firstUserMessage: firstUser.content) }
            }
        } catch {
            Self.log("Streaming error: \(error.localizedDescription)")
            if messages.last?.role == .assistant {
                let partial = messages.removeLast()
                if let id = partial.id { try? db.deleteMessage(id: id) }
            }
            failedUserMessageId = failedUserMsgId
            errorMessage = friendlyError(error)
        }
        Self.log("streamAssistantReply EXIT convId=\(convId) (vm=\(Unmanaged.passUnretained(self).toOpaque()))")
    }

    // MARK: - Auto-title

    private func generateTitle(for convId: Int64, firstUserMessage: String) async {
        Self.log("generateTitle start for convId=\(convId)")
        let titlePrompt = PromptTemplates.conversationTitleUser(firstMessage: firstUserMessage)

        guard let response = try? await claude.send(
            userMessage: titlePrompt,
            systemPrompt: PromptTemplates.conversationTitleSystem,
            maxTokens: 30
        ) else {
            Self.log("generateTitle: no response (send failed)")
            return
        }

        let raw = response.text
        Self.log("generateTitle raw: \(raw.prefix(80))")

        let title = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            .prefix(80)
            .description

        guard !title.isEmpty else {
            Self.log("generateTitle: empty after trimming")
            return
        }

        guard var conv = conversation, conv.id == convId else {
            Self.log("generateTitle: conversation changed or missing")
            return
        }
        conv.title = title
        try? db.updateConversationTitle(conv)

        conversation = conv
        if let idx = conversations.firstIndex(where: { $0.id == convId }) {
            conversations[idx] = conv
        }
        Self.log("generateTitle done. Title set to: \(title)")
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
