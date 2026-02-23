import Foundation

// MARK: - URLSession protocols for testability

/// Allows `ClaudeService` non-streaming path to be tested without real network calls.
protocol URLSessionDataTasking {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionDataTasking {}

/// Allows `ClaudeService` streaming path to be tested without real network calls.
///
/// Returns an async sequence of lines from the response body.
protocol URLSessionBytesTasking {
    func lines(for request: URLRequest) -> AsyncThrowingStream<String, Error>
}

extension URLSession: URLSessionBytesTasking {
    func lines(for request: URLRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (asyncBytes, response) = try await self.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        continuation.finish(throwing: NetworkError.unexpectedResponse("Non-HTTP response"))
                        return
                    }
                    guard http.statusCode == 200 else {
                        // Collect body for error detail then surface a typed error.
                        var body = ""
                        for try await byte in asyncBytes {
                            body.append(Character(UnicodeScalar(byte)))
                        }
                        let err = ClaudeService.mapHTTPError(statusCode: http.statusCode, body: body)
                        continuation.finish(throwing: err)
                        return
                    }
                    for try await line in asyncBytes.lines {
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// URLSession-based client for the Anthropic Claude Messages API.
///
/// Responsibilities:
/// - Fetches the API key from KeychainService before every request.
/// - Serialises `ClaudeRequest` to JSON and deserialises `ClaudeResponse`.
/// - Maps HTTP/network failures to typed `NetworkError` values.
/// - Retries once on transient failures (5xx, timeout) with exponential back-off.
/// - Supports streaming via `streamConversation()` using SSE / `URLSession.bytes(for:)`.
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
        /// Generous timeout for streaming responses: `claude-opus-4-6` generating 2 048 tokens
        /// can take well over 30 s on a mobile connection, so we allow 5 minutes before giving up.
        static let streamingTimeoutInterval: TimeInterval = 300
        static let maxRetries  = 1
    }

    // MARK: - Dependencies

    private let session: URLSessionDataTasking
    private let bytesSession: URLSessionBytesTasking
    private let keychain: KeychainStoring
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    // MARK: - Init

    init(
        session: URLSessionDataTasking = URLSession(configuration: .ephemeral),
        bytesSession: URLSessionBytesTasking = URLSession(configuration: .ephemeral),
        keychain: KeychainStoring = KeychainService.shared
    ) {
        self.session = session
        self.bytesSession = bytesSession
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

    /// Sends a full conversation history to Claude and returns the assistant's next reply.
    ///
    /// Use this for multi-turn chat where prior messages must be included.
    ///
    /// - Parameters:
    ///   - messages: Ordered list of prior turns (user + assistant), followed by the new user turn.
    ///   - systemPrompt: Optional system context.
    ///   - model: The Claude model to use. Defaults to `claude-opus-4-6`.
    ///   - maxTokens: Maximum tokens in the response.
    func sendConversation(
        messages: [Message],
        systemPrompt: String? = nil,
        model: String = Constant.defaultModel,
        maxTokens: Int = 2048
    ) async throws -> ClaudeResponse {
        let apiKey = try fetchAPIKey()

        let claudeMessages = messages.map { msg in
            ClaudeMessage(
                role: msg.role == .user ? .user : .assistant,
                content: msg.content
            )
        }

        let request = ClaudeRequest(
            model: model,
            maxTokens: maxTokens,
            system: systemPrompt,
            messages: claudeMessages
        )

        return try await perform(request, apiKey: apiKey, attempt: 0)
    }

    /// Streams a full conversation history to Claude, yielding incremental text chunks.
    ///
    /// The returned `AsyncThrowingStream` emits each `text_delta` chunk as it arrives
    /// from the server-sent event stream. Callers should append chunks to an in-progress
    /// message so the UI updates token-by-token.
    ///
    /// - Parameters:
    ///   - messages: Full conversation history ending with the new user turn.
    ///   - systemPrompt: Optional system context.
    ///   - model: The Claude model to use.
    ///   - maxTokens: Maximum tokens in the response.
    /// - Returns: An `AsyncThrowingStream` of text chunk strings.
    func streamConversation(
        messages: [Message],
        systemPrompt: String? = nil,
        model: String = Constant.defaultModel,
        maxTokens: Int = 2048
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let apiKey = try fetchAPIKey()

                    let claudeMessages = messages.map { msg in
                        ClaudeMessage(
                            role: msg.role == .user ? .user : .assistant,
                            content: msg.content
                        )
                    }

                    let claudeRequest = ClaudeRequest(
                        model: model,
                        maxTokens: maxTokens,
                        system: systemPrompt,
                        messages: claudeMessages,
                        stream: true
                    )

                    let urlRequest = try buildURLRequest(claudeRequest, apiKey: apiKey,
                                                        timeout: Constant.streamingTimeoutInterval)

                    for try await line in bytesSession.lines(for: urlRequest) {
                        // SSE lines have the form: "data: {json}" or blank (heartbeat).
                        guard line.hasPrefix("data: ") else { continue }

                        let jsonString = String(line.dropFirst(6)) // drop "data: "

                        guard let data = jsonString.data(using: .utf8) else { continue }

                        let event: SSEEvent
                        do {
                            event = try decoder.decode(SSEEvent.self, from: data)
                        } catch {
                            // Skip unparseable events (e.g. ping, message_start without delta)
                            continue
                        }

                        // Anthropic signals end-of-response with message_stop.
                        // Break immediately rather than waiting for the TCP connection to close,
                        // which can hang indefinitely on some iOS/network configurations.
                        if event.type == "message_stop" { break }

                        if event.type == "content_block_delta",
                           event.delta?.type == "text_delta",
                           let chunk = event.delta?.text,
                           !chunk.isEmpty {
                            continuation.yield(chunk)
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            // Cancel the backing Task if the consumer exits early (view disappears, etc.)
            continuation.onTermination = { _ in task.cancel() }
        }
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

    private func buildURLRequest(
        _ request: ClaudeRequest,
        apiKey: String,
        timeout: TimeInterval = Constant.timeoutInterval
    ) throws -> URLRequest {
        guard let url = URL(string: Constant.baseURL) else {
            throw NetworkError.unexpectedResponse("Invalid base URL")
        }

        var urlRequest = URLRequest(url: url, timeoutInterval: timeout)
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
        ClaudeService.mapURLError(error)
    }

    /// Maps a `URLError` to a typed `NetworkError`. `static` so it can be called from extensions.
    static func mapURLError(_ error: URLError) -> NetworkError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost:
            return .noConnection
        case .timedOut:
            return .timeout
        default:
            return .httpError(statusCode: -1, message: error.localizedDescription)
        }
    }

    /// Maps an HTTP status code + raw body string to a typed `NetworkError`.
    /// `static` so it can be called from the `URLSessionBytesTasking` extension on `URLSession`.
    static func mapHTTPError(statusCode: Int, body: String) -> NetworkError {
        switch statusCode {
        case 401:
            return .invalidAPIKey
        case 429:
            return .rateLimited(retryAfter: nil)
        default:
            // Try to extract a message from the error body.
            let message = (try? JSONDecoder().decode(ClaudeAPIError.self, from: Data(body.utf8)))?.error.message
            return .httpError(statusCode: statusCode, message: message)
        }
    }
}
