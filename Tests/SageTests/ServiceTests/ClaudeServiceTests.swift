import XCTest
@testable import Sage

// MARK: - Mock URLSession

final class ClaudeServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeService(
        data: Data? = nil,
        response: URLResponse? = nil,
        error: Error? = nil,
        apiKey: String? = "sk-ant-test"
    ) -> ClaudeService {
        let keychain = MockKeychain(key: apiKey)
        let session = MockURLSession(mockData: data, mockResponse: response, mockError: error)
        return ClaudeService(session: session, keychain: keychain)
    }

    private func ok200() -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://api.anthropic.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    }

    private func http(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://api.anthropic.com")!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    private var validResponseData: Data {
        let json = """
        {
          "id": "msg_01",
          "type": "message",
          "role": "assistant",
          "content": [{"type": "text", "text": "Hello!"}],
          "model": "claude-opus-4-6",
          "stop_reason": "end_turn",
          "usage": {"input_tokens": 10, "output_tokens": 5}
        }
        """
        return Data(json.utf8)
    }

    // MARK: - Success

    func testSend_returnsDecodedResponse() async throws {
        let svc = makeService(data: validResponseData, response: ok200())
        let result = try await svc.send(userMessage: "Hi")
        XCTAssertEqual(result.text, "Hello!")
        XCTAssertEqual(result.id, "msg_01")
    }

    // MARK: - Missing API Key

    func testSend_throwsMissingAPIKey_whenNoKeyStored() async {
        let svc = makeService(apiKey: nil)
        do {
            _ = try await svc.send(userMessage: "Hi")
            XCTFail("Expected missingAPIKey")
        } catch NetworkError.missingAPIKey {
            // pass
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - HTTP Errors

    func testSend_throwsInvalidAPIKey_on401() async {
        let errorBody = Data("""
        {"type":"error","error":{"type":"authentication_error","message":"Invalid API key"}}
        """.utf8)
        let svc = makeService(data: errorBody, response: http(401))
        do {
            _ = try await svc.send(userMessage: "Hi")
            XCTFail("Expected invalidAPIKey")
        } catch NetworkError.invalidAPIKey {
            // pass
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSend_throwsRateLimited_on429() async {
        let svc = makeService(data: Data(), response: http(429))
        do {
            _ = try await svc.send(userMessage: "Hi")
            XCTFail("Expected rateLimited")
        } catch NetworkError.rateLimited {
            // pass
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSend_throwsHTTPError_on400() async {
        let errorBody = Data("""
        {"type":"error","error":{"type":"invalid_request_error","message":"Bad param"}}
        """.utf8)
        let svc = makeService(data: errorBody, response: http(400))
        do {
            _ = try await svc.send(userMessage: "Hi")
            XCTFail("Expected httpError")
        } catch NetworkError.httpError(let code, _) {
            XCTAssertEqual(code, 400)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Connectivity

    func testSend_throwsNoConnection_onNotConnectedError() async {
        let urlError = URLError(.notConnectedToInternet)
        let svc = makeService(error: urlError)
        do {
            _ = try await svc.send(userMessage: "Hi")
            XCTFail("Expected noConnection")
        } catch NetworkError.noConnection {
            // pass
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Decoding

    func testSend_throwsDecodingFailed_onMalformedJSON() async {
        let svc = makeService(data: Data("not-json".utf8), response: ok200())
        do {
            _ = try await svc.send(userMessage: "Hi")
            XCTFail("Expected decodingFailed")
        } catch NetworkError.decodingFailed {
            // pass
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - Test Doubles

private struct MockKeychain: KeychainStoring {
    let key: String?
    func set(_ value: String, for k: KeychainService.Key) throws {}
    func get(_ k: KeychainService.Key) throws -> String? { key }
    @discardableResult func delete(_ k: KeychainService.Key) -> Bool { true }
}

/// Stub that satisfies `URLSessionDataTasking` without touching the real network.
private struct MockURLSession: URLSessionDataTasking {
    let mockData: Data?
    let mockResponse: URLResponse?
    let mockError: Error?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let error = mockError { throw error }
        return (mockData ?? Data(), mockResponse ?? URLResponse())
    }
}
