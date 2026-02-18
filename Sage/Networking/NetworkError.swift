import Foundation

/// Errors that can be thrown by the Claude API client and related networking code.
enum NetworkError: Error, LocalizedError, Equatable {

    // MARK: - Configuration

    /// No API key is stored in the Keychain.
    case missingAPIKey

    /// The stored API key was rejected by the API (HTTP 401).
    case invalidAPIKey

    // MARK: - HTTP

    /// The server returned an unexpected HTTP status code.
    case httpError(statusCode: Int, message: String?)

    /// The server indicated the client is sending too many requests (HTTP 429).
    case rateLimited(retryAfter: TimeInterval?)

    // MARK: - Connectivity

    /// No network connection is available.
    case noConnection

    /// The request timed out.
    case timeout

    // MARK: - Data

    /// The response body could not be decoded into the expected type.
    case decodingFailed(String)

    /// The response body contained valid JSON but an unexpected shape.
    case unexpectedResponse(String)

    // MARK: - LocalizedError

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No API key found. Please add your Anthropic API key in Settings."
        case .invalidAPIKey:
            return "The API key is invalid or has been revoked."
        case .httpError(let code, let msg):
            if let msg { return "Server error \(code): \(msg)" }
            return "Server error \(code)."
        case .rateLimited(let after):
            if let after { return "Rate limited. Retry after \(Int(after))s." }
            return "Rate limited. Please wait before retrying."
        case .noConnection:
            return "No internet connection. Check your network and try again."
        case .timeout:
            return "The request timed out. Please try again."
        case .decodingFailed(let detail):
            return "Failed to decode response: \(detail)"
        case .unexpectedResponse(let detail):
            return "Unexpected response from server: \(detail)"
        }
    }

    // MARK: - Equatable

    static func == (lhs: NetworkError, rhs: NetworkError) -> Bool {
        switch (lhs, rhs) {
        case (.missingAPIKey, .missingAPIKey):          return true
        case (.invalidAPIKey, .invalidAPIKey):          return true
        case (.noConnection, .noConnection):            return true
        case (.timeout, .timeout):                      return true
        case (.httpError(let a, _), .httpError(let b, _)):   return a == b
        case (.rateLimited, .rateLimited):              return true
        case (.decodingFailed(let a), .decodingFailed(let b)): return a == b
        case (.unexpectedResponse(let a), .unexpectedResponse(let b)): return a == b
        default: return false
        }
    }
}
