import Foundation

// MARK: - URLSession protocol for testability

/// Allows `ClaudeService` to be tested without real network calls.
protocol URLSessionDataTasking {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionDataTasking {}

/// URLSession-based client for the Anthropic Claude Messages API.
///
/// Responsibilities:
/// - Fetches the API key from KeychainService before every request.
/// - Serialises `ClaudeRequest` to JSON and deserialises `ClaudeResponse`.
/// - Maps HTTP/network failures to typed `NetworkError` values.
/// - Retries once on transient failures (5xx, timeout) with exponential back-off.
final class ClaudeService {

    // MARK: - Singleton

    static let shared = ClaudeService()

    // MARK: - Constants

    private enum Constant {
        static let baseURL     = "https://api.anthropic.com/v1/messages"
        static let apiVersion  = "2023-06-01"
        static let defaultModel = "claude-opus-4-6"
        static let maxTokens   = 1024
        static let timeoutInterval: TimeInterval = 30
        static let maxRetries  = 1
    }

    // MARK: - Dependencies

    private let session: URLSessionDataTasking
    private let keychain: KeychainStoring
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    // MARK: - Init

    init(
        session: URLSessionDataTasking = URLSession(configuration: .ephemeral),
        keychain: KeychainStoring = KeychainService.shared
    ) {
        self.session = session
        self.keychain = keychain
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    // MARK: - Public API

    /// Sends a single user message to Claude and returns the full response.
    ///
    /// - Parameters:
    ///   - userMessage: The user's prompt text.
    ///   - systemPrompt: Optional system context prepended to the conversation.
    ///   - model: The Claude model to use. Defaults to `claude-opus-4-6`.
    ///   - maxTokens: Maximum tokens in the response.
    /// - Returns: The decoded `ClaudeResponse`.
    /// - Throws: `NetworkError` for all failure cases.
    func send(
        userMessage: String,
        systemPrompt: String? = nil,
        model: String = Constant.defaultModel,
        maxTokens: Int = Constant.maxTokens
    ) async throws -> ClaudeResponse {
        let apiKey = try fetchAPIKey()

        let request = ClaudeRequest(
            model: model,
            maxTokens: maxTokens,
            system: systemPrompt,
            messages: [ClaudeMessage(role: .user, content: userMessage)]
        )

        return try await perform(request, apiKey: apiKey, attempt: 0)
    }

    // MARK: - Private

    private func fetchAPIKey() throws -> String {
        do {
            guard let key = try keychain.get(.anthropicAPIKey), !key.isEmpty else {
                throw NetworkError.missingAPIKey
            }
            return key
        } catch is NetworkError {
            throw NetworkError.missingAPIKey
        } catch {
            throw NetworkError.missingAPIKey
        }
    }

    private func perform(
        _ request: ClaudeRequest,
        apiKey: String,
        attempt: Int
    ) async throws -> ClaudeResponse {
        let urlRequest = try buildURLRequest(request, apiKey: apiKey)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let urlError as URLError {
            throw mapURLError(urlError)
        }

        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.unexpectedResponse("Non-HTTP response")
        }

        switch http.statusCode {
        case 200...299:
            return try decodeResponse(data)

        case 401:
            throw NetworkError.invalidAPIKey

        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After")
                .flatMap(TimeInterval.init)
            throw NetworkError.rateLimited(retryAfter: retryAfter)

        case 500...599 where attempt < Constant.maxRetries:
            let delay = pow(2.0, Double(attempt))
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            return try await perform(request, apiKey: apiKey, attempt: attempt + 1)

        default:
            let message = try? decoder.decode(ClaudeAPIError.self, from: data)
            throw NetworkError.httpError(statusCode: http.statusCode, message: message?.error.message)
        }
    }

    private func buildURLRequest(_ request: ClaudeRequest, apiKey: String) throws -> URLRequest {
        guard let url = URL(string: Constant.baseURL) else {
            throw NetworkError.unexpectedResponse("Invalid base URL")
        }

        var urlRequest = URLRequest(url: url, timeoutInterval: Constant.timeoutInterval)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(Constant.apiVersion, forHTTPHeaderField: "anthropic-version")

        do {
            urlRequest.httpBody = try encoder.encode(request)
        } catch {
            throw NetworkError.unexpectedResponse("Failed to encode request: \(error.localizedDescription)")
        }

        return urlRequest
    }

    private func decodeResponse(_ data: Data) throws -> ClaudeResponse {
        do {
            return try decoder.decode(ClaudeResponse.self, from: data)
        } catch {
            throw NetworkError.decodingFailed(error.localizedDescription)
        }
    }

    private func mapURLError(_ error: URLError) -> NetworkError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost:
            return .noConnection
        case .timedOut:
            return .timeout
        default:
            return .httpError(statusCode: -1, message: error.localizedDescription)
        }
    }
}
