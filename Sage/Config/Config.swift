import Foundation

/// App-wide configuration constants.
enum Config {

    // MARK: - Claude API

    enum Claude {
        /// The default Claude model used for metric suggestions and coaching.
        static let defaultModel = "claude-opus-4-6"

        /// Maximum output tokens for metric-suggestion requests.
        static let metricSuggestionMaxTokens = 512

        /// Maximum output tokens for general coaching responses.
        static let coachingMaxTokens = 1024

        /// API base URL.
        static let apiBaseURL = "https://api.anthropic.com/v1/messages"

        /// API version header value.
        static let apiVersion = "2023-06-01"

        /// Number of retries on transient 5xx errors.
        static let maxRetries = 1
    }

    // MARK: - Network

    enum Network {
        /// Default URLRequest timeout in seconds.
        static let timeoutInterval: TimeInterval = 30
    }
}
