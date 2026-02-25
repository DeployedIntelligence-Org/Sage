import Foundation

// MARK: - Response

/// Top-level response from the Claude Messages API.
struct ClaudeResponse: Decodable {
    let id: String
    let type: String
    let role: String
    let content: [ContentBlock]
    let model: String
    let stopReason: String?
    let usage: Usage

    enum CodingKeys: String, CodingKey {
        case id, type, role, content, model, usage
        case stopReason = "stop_reason"
    }

    /// The concatenated text from all text content blocks.
    var text: String {
        content.compactMap { block in
            if case .text(let t) = block { return t }
            return nil
        }.joined()
    }
}

// MARK: - Content Block

enum ContentBlock: Decodable {
    case text(String)
    case unknown

    private enum CodingKeys: String, CodingKey {
        case type, text
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        if type == "text", let text = try? container.decode(String.self, forKey: .text) {
            self = .text(text)
        } else {
            self = .unknown
        }
    }
}

// MARK: - Usage

struct Usage: Decodable {
    let inputTokens: Int
    let outputTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens  = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

// MARK: - API Error Response

/// Error body returned by the Claude API on non-2xx responses.
struct ClaudeAPIError: Decodable {
    let type: String
    let error: APIErrorDetail
}

struct APIErrorDetail: Decodable {
    let type: String
    let message: String
}

// MARK: - Server-Sent Event (SSE) models

/// Top-level SSE event envelope: `{"type":"content_block_delta", ...}` etc.
struct SSEEvent: Decodable {
    let type: String
    let delta: SSEDelta?
    let message: SSEMessageStart?
}

/// The `delta` field present in `content_block_delta` and `message_delta` events.
struct SSEDelta: Decodable {
    let type: String?
    let text: String?
    /// Present on `message_delta` events when the provider signals completion.
    let stopReason: String?

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case stopReason = "stop_reason"
    }
}

/// The `message` field present in `message_start` events (carries usage).
struct SSEMessageStart: Decodable {
    let usage: SSEUsage?
}

struct SSEUsage: Decodable {
    let inputTokens: Int?
    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
    }
}
