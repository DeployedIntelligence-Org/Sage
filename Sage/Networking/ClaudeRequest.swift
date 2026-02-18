import Foundation

// MARK: - Request

/// Top-level request body sent to the Claude Messages API.
struct ClaudeRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String?
    let messages: [ClaudeMessage]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
    }
}

// MARK: - Message

/// A single turn in the conversation.
struct ClaudeMessage: Encodable {
    let role: Role
    let content: String

    enum Role: String, Encodable {
        case user
        case assistant
    }
}
