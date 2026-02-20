import XCTest
@testable import Sage

@MainActor
final class ChatViewModelTests: XCTestCase {

    // MARK: - Helpers

    /// Creates an isolated DatabaseService backed by a temp file.
    private func makeTempDB() throws -> (DatabaseService, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("test.db")
        let db = DatabaseService(url: url)
        try db.open()
        return (db, dir)
    }

    private func makeViewModel(
        skillGoal: SkillGoal = SkillGoal(id: 1, skillName: "Piano"),
        db: DatabaseService,
        claude: ClaudeService
    ) -> ChatViewModel {
        ChatViewModel(skillGoal: skillGoal, db: db, claude: claude)
    }

    /// Builds well-formed SSE lines for a sequence of text chunks (for streaming tests).
    private func sseLines(chunks: [String]) -> [String] {
        var lines = chunks.map { chunk -> String in
            let json = "{\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"\(chunk)\"}}"
            return "data: \(json)"
        }
        lines.append("data: [DONE]")
        return lines
    }

    private func makeClaudeService(
        data: Data? = nil,
        response: URLResponse? = nil,
        error: Error? = nil,
        streamLines: [String]? = nil,
        streamError: Error? = nil,
        apiKey: String? = "sk-ant-test"
    ) -> ClaudeService {
        let keychain = MockKeychain(key: apiKey)
        let session = MockURLSession(mockData: data, mockResponse: response, mockError: error)
        let bytesSession = MockBytesSession(
            mockLines: streamLines ?? sseLines(chunks: ["Great question! Keep practising."]),
            mockError: streamError
        )
        return ClaudeService(session: session, bytesSession: bytesSession, keychain: keychain)
    }

    private func ok200() -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    // successResponseData is retained for compilation compatibility; streaming tests use sseLines().
    private var successResponseData: Data {
        let json = """
        {
          "id": "msg_01",
          "type": "message",
          "role": "assistant",
          "content": [{"type": "text", "text": "Great question! Keep practising."}],
          "model": "claude-opus-4-6",
          "stop_reason": "end_turn",
          "usage": {"input_tokens": 20, "output_tokens": 10}
        }
        """
        return Data(json.utf8)
    }

    // MARK: - loadConversation

    func testLoadConversation_createsConversationWhenNoneExists() async throws {
        let (db, dir) = try makeTempDB()
        defer { db.close(); try? FileManager.default.removeItem(at: dir) }

        let goal = try db.insert(SkillGoal(skillName: "Guitar"))
        let claude = makeClaudeService()
        let vm = makeViewModel(skillGoal: goal, db: db, claude: claude)

        await vm.loadConversation()

        // A conversation should have been auto-created.
        let convs = try db.fetchConversations(skillGoalId: goal.id!)
        XCTAssertEqual(convs.count, 1)
    }

    func testLoadConversation_loadsExistingMessages() async throws {
        let (db, dir) = try makeTempDB()
        defer { db.close(); try? FileManager.default.removeItem(at: dir) }

        let goal = try db.insert(SkillGoal(skillName: "Chess"))
        let conv = try db.insert(Conversation(skillGoalId: goal.id, title: "Session"))
        try db.insert(Message(conversationId: conv.id!, role: .user,      content: "Hi"))
        try db.insert(Message(conversationId: conv.id!, role: .assistant, content: "Hello!"))

        let claude = makeClaudeService()
        let vm = makeViewModel(skillGoal: goal, db: db, claude: claude)
        await vm.loadConversation()

        XCTAssertEqual(vm.messages.count, 2)
        XCTAssertEqual(vm.messages[0].content, "Hi")
        XCTAssertEqual(vm.messages[1].content, "Hello!")
    }

    func testLoadConversation_messagesStartEmpty_beforeLoad() async throws {
        let (db, dir) = try makeTempDB()
        defer { db.close(); try? FileManager.default.removeItem(at: dir) }

        let goal = try db.insert(SkillGoal(skillName: "Running"))
        let claude = makeClaudeService()
        let vm = makeViewModel(skillGoal: goal, db: db, claude: claude)

        XCTAssertTrue(vm.messages.isEmpty)
    }

    // MARK: - sendMessage — happy path (streaming)

    func testSendMessage_appendsUserMessageImmediately() async throws {
        let (db, dir) = try makeTempDB()
        defer { db.close(); try? FileManager.default.removeItem(at: dir) }

        let goal = try db.insert(SkillGoal(skillName: "Yoga"))
        let claude = makeClaudeService()
        let vm = makeViewModel(skillGoal: goal, db: db, claude: claude)
        await vm.loadConversation()

        vm.inputText = "How do I improve?"
        await vm.sendMessage()

        // Both user and assistant messages should appear.
        XCTAssertEqual(vm.messages.count, 2)
        XCTAssertEqual(vm.messages[0].role, .user)
        XCTAssertEqual(vm.messages[0].content, "How do I improve?")
    }

    func testSendMessage_appendsAssistantReply() async throws {
        let (db, dir) = try makeTempDB()
        defer { db.close(); try? FileManager.default.removeItem(at: dir) }

        let goal = try db.insert(SkillGoal(skillName: "Cooking"))
        // Deliver the reply in two chunks to verify they are concatenated.
        let claude = makeClaudeService(streamLines: sseLines(chunks: ["Great question!", " Keep practising."]))
        let vm = makeViewModel(skillGoal: goal, db: db, claude: claude)
        await vm.loadConversation()

        vm.inputText = "Tips please"
        await vm.sendMessage()

        XCTAssertEqual(vm.messages.last?.role, .assistant)
        XCTAssertEqual(vm.messages.last?.content, "Great question! Keep practising.")
    }

    func testSendMessage_streamsChunksIntoSingleBubble() async throws {
        let (db, dir) = try makeTempDB()
        defer { db.close(); try? FileManager.default.removeItem(at: dir) }

        let goal = try db.insert(SkillGoal(skillName: "Piano"))
        let chunks = ["Hello", ", ", "world", "!"]
        let claude = makeClaudeService(streamLines: sseLines(chunks: chunks))
        let vm = makeViewModel(skillGoal: goal, db: db, claude: claude)
        await vm.loadConversation()

        vm.inputText = "Hi"
        await vm.sendMessage()

        // Streaming must not produce multiple assistant messages.
        let assistantMessages = vm.messages.filter { $0.role == .assistant }
        XCTAssertEqual(assistantMessages.count, 1)
        XCTAssertEqual(assistantMessages[0].content, chunks.joined())
    }

    func testSendMessage_clearsInputText() async throws {
        let (db, dir) = try makeTempDB()
        defer { db.close(); try? FileManager.default.removeItem(at: dir) }

        let goal = try db.insert(SkillGoal(skillName: "Drawing"))
        let claude = makeClaudeService()
        let vm = makeViewModel(skillGoal: goal, db: db, claude: claude)
        await vm.loadConversation()

        vm.inputText = "What should I practice?"
        await vm.sendMessage()

        XCTAssertTrue(vm.inputText.isEmpty)
    }

    func testSendMessage_persistsMessagesToDatabase() async throws {
        let (db, dir) = try makeTempDB()
        defer { db.close(); try? FileManager.default.removeItem(at: dir) }

        let goal = try db.insert(SkillGoal(skillName: "Spanish"))
        let claude = makeClaudeService(streamLines: sseLines(chunks: ["Hola de vuelta!"]))
        let vm = makeViewModel(skillGoal: goal, db: db, claude: claude)
        await vm.loadConversation()

        vm.inputText = "Hola!"
        await vm.sendMessage()

        let convs = try db.fetchConversations(skillGoalId: goal.id!)
        let msgs = try db.fetchMessages(conversationId: convs.first!.id!)
        XCTAssertEqual(msgs.count, 2)
        XCTAssertEqual(msgs[0].role, .user)
        XCTAssertEqual(msgs[1].role, .assistant)
        // The persisted content must equal the fully assembled reply.
        XCTAssertEqual(msgs[1].content, "Hola de vuelta!")
    }

    // MARK: - sendMessage — guard clauses

    func testSendMessage_doesNothingWhenInputEmpty() async throws {
        let (db, dir) = try makeTempDB()
        defer { db.close(); try? FileManager.default.removeItem(at: dir) }

        let goal = try db.insert(SkillGoal(skillName: "Piano"))
        let claude = makeClaudeService()
        let vm = makeViewModel(skillGoal: goal, db: db, claude: claude)
        await vm.loadConversation()

        vm.inputText = "   "
        await vm.sendMessage()

        XCTAssertTrue(vm.messages.isEmpty)
    }

    // MARK: - sendMessage — error handling

    func testSendMessage_setsErrorMessage_onMissingAPIKey() async throws {
        let (db, dir) = try makeTempDB()
        defer { db.close(); try? FileManager.default.removeItem(at: dir) }

        let goal = try db.insert(SkillGoal(skillName: "Drums"))
        let claude = makeClaudeService(apiKey: nil)
        let vm = makeViewModel(skillGoal: goal, db: db, claude: claude)
        await vm.loadConversation()

        vm.inputText = "Help!"
        await vm.sendMessage()

        XCTAssertNotNil(vm.errorMessage, "Should surface an error when the API key is missing")
        XCTAssertTrue(
            vm.errorMessage!.lowercased().contains("api key"),
            "Error message should mention the API key"
        )
    }

    func testSendMessage_removesPartialBubble_onStreamError() async throws {
        let (db, dir) = try makeTempDB()
        defer { db.close(); try? FileManager.default.removeItem(at: dir) }

        let goal = try db.insert(SkillGoal(skillName: "Coding"))
        let streamErr = URLError(.notConnectedToInternet)
        let claude = makeClaudeService(streamError: streamErr)
        let vm = makeViewModel(skillGoal: goal, db: db, claude: claude)
        await vm.loadConversation()

        vm.inputText = "What should I learn next?"
        await vm.sendMessage()

        // The partial assistant bubble should have been removed on error.
        XCTAssertFalse(vm.messages.contains { $0.role == .assistant },
            "Partial assistant bubble should be removed on stream failure")
        XCTAssertNotNil(vm.errorMessage)
    }

    func testSendMessage_isLoading_isFalseAfterCompletion() async throws {
        let (db, dir) = try makeTempDB()
        defer { db.close(); try? FileManager.default.removeItem(at: dir) }

        let goal = try db.insert(SkillGoal(skillName: "Writing"))
        let claude = makeClaudeService()
        let vm = makeViewModel(skillGoal: goal, db: db, claude: claude)
        await vm.loadConversation()

        vm.inputText = "Give me a tip"
        await vm.sendMessage()

        XCTAssertFalse(vm.isLoading, "isLoading should be false after send completes")
    }

    // MARK: - Conversation list management

    func testLoadConversation_populatesConversationsList() async throws {
        let (db, dir) = try makeTempDB()
        defer { db.close(); try? FileManager.default.removeItem(at: dir) }

        let goal = try db.insert(SkillGoal(skillName: "Photography"))
        try db.insert(Conversation(skillGoalId: goal.id, title: "Session A"))
        try db.insert(Conversation(skillGoalId: goal.id, title: "Session B"))

        let claude = makeClaudeService()
        let vm = makeViewModel(skillGoal: goal, db: db, claude: claude)
        await vm.loadConversation()

        XCTAssertEqual(vm.conversations.count, 2)
    }

    func testNewConversation_addsToConversationsList() async throws {
        let (db, dir) = try makeTempDB()
        defer { db.close(); try? FileManager.default.removeItem(at: dir) }

        let goal = try db.insert(SkillGoal(skillName: "Violin"))
        let claude = makeClaudeService()
        let vm = makeViewModel(skillGoal: goal, db: db, claude: claude)
        await vm.loadConversation()

        let countBefore = vm.conversations.count
        await vm.newConversation()

        XCTAssertEqual(vm.conversations.count, countBefore + 1)
    }

    func testNewConversation_clearsMessages() async throws {
        let (db, dir) = try makeTempDB()
        defer { db.close(); try? FileManager.default.removeItem(at: dir) }

        let goal = try db.insert(SkillGoal(skillName: "Cello"))
        let conv = try db.insert(Conversation(skillGoalId: goal.id, title: "Old"))
        try db.insert(Message(conversationId: conv.id!, role: .user, content: "Hi"))

        let claude = makeClaudeService()
        let vm = makeViewModel(skillGoal: goal, db: db, claude: claude)
        await vm.loadConversation()

        XCTAssertFalse(vm.messages.isEmpty, "Should have pre-existing messages")

        await vm.newConversation()

        XCTAssertTrue(vm.messages.isEmpty, "New conversation should start empty")
    }

    func testDeleteConversation_removesFromList() async throws {
        let (db, dir) = try makeTempDB()
        defer { db.close(); try? FileManager.default.removeItem(at: dir) }

        let goal = try db.insert(SkillGoal(skillName: "Flute"))
        try db.insert(Conversation(skillGoalId: goal.id, title: "Conv 1"))
        try db.insert(Conversation(skillGoalId: goal.id, title: "Conv 2"))

        let claude = makeClaudeService()
        let vm = makeViewModel(skillGoal: goal, db: db, claude: claude)
        await vm.loadConversation()

        let toDelete = vm.conversations[0]
        await vm.deleteConversation(toDelete)

        XCTAssertFalse(vm.conversations.contains { $0.id == toDelete.id },
                       "Deleted conversation should be removed from the list")
    }

    func testDeleteConversation_createsNewOne_whenLastDeleted() async throws {
        let (db, dir) = try makeTempDB()
        defer { db.close(); try? FileManager.default.removeItem(at: dir) }

        let goal = try db.insert(SkillGoal(skillName: "Oboe"))
        let claude = makeClaudeService()
        let vm = makeViewModel(skillGoal: goal, db: db, claude: claude)
        await vm.loadConversation()

        // There should be exactly 1 auto-created conversation.
        XCTAssertEqual(vm.conversations.count, 1)
        let only = vm.conversations[0]
        await vm.deleteConversation(only)

        // After deleting the last one, a fresh conversation must be created automatically.
        XCTAssertEqual(vm.conversations.count, 1, "Should auto-create a new conversation")
        XCTAssertNotEqual(vm.conversations[0].id, only.id, "New conversation should have a different id")
    }
}

// MARK: - Test Doubles

private struct MockKeychain: KeychainStoring {
    let key: String?
    func set(_ value: String, for k: KeychainService.Key) throws {}
    func get(_ k: KeychainService.Key) throws -> String? { key }
    @discardableResult func delete(_ k: KeychainService.Key) -> Bool { true }
}

private struct MockURLSession: URLSessionDataTasking {
    let mockData: Data?
    let mockResponse: URLResponse?
    let mockError: Error?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let error = mockError { throw error }
        return (mockData ?? Data(), mockResponse ?? URLResponse())
    }
}

private struct MockBytesSession: URLSessionBytesTasking {
    let mockLines: [String]
    let mockError: Error?

    func lines(for request: URLRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            if let error = mockError {
                continuation.finish(throwing: error)
                return
            }
            for line in mockLines {
                continuation.yield(line)
            }
            continuation.finish()
        }
    }
}
