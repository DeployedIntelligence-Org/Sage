import XCTest
@testable import Sage

final class CostCalculatorTests: XCTestCase {

    private func usage(input: Int, output: Int) -> Usage {
        // Decode via JSON to construct Usage (all stored properties private).
        let json = """
        {"input_tokens": \(input), "output_tokens": \(output)}
        """
        return try! JSONDecoder().decode(Usage.self, from: Data(json.utf8))
    }

    func testEstimatedCost_zeroTokens_isZero() {
        let cost = CostCalculator.estimatedCost(for: usage(input: 0, output: 0))
        XCTAssertEqual(cost, 0.0, accuracy: 1e-9)
    }

    func testEstimatedCost_oneMillionInputTokens() {
        // 1M input tokens at $15/M = $15
        let cost = CostCalculator.estimatedCost(for: usage(input: 1_000_000, output: 0))
        XCTAssertEqual(cost, 15.0, accuracy: 0.001)
    }

    func testEstimatedCost_oneMillionOutputTokens() {
        // 1M output tokens at $75/M = $75
        let cost = CostCalculator.estimatedCost(for: usage(input: 0, output: 1_000_000))
        XCTAssertEqual(cost, 75.0, accuracy: 0.001)
    }

    func testEstimatedCost_mixedTokens() {
        // 100 input + 50 output
        let cost = CostCalculator.estimatedCost(for: usage(input: 100, output: 50))
        let expected = 100.0 / 1_000_000 * 15.0 + 50.0 / 1_000_000 * 75.0
        XCTAssertEqual(cost, expected, accuracy: 1e-9)
    }

    func testFormatted_correctPrefix() {
        let result = CostCalculator.formatted(0.0023)
        XCTAssertTrue(result.hasPrefix("$"), "Formatted cost should start with '$'")
    }

    func testFormatted_fourDecimalPlaces() {
        let result = CostCalculator.formatted(0.0)
        // "$0.0000"
        XCTAssertEqual(result, "$0.0000")
    }
}
