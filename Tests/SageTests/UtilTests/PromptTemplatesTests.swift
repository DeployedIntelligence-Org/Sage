import XCTest
@testable import Sage

final class PromptTemplatesTests: XCTestCase {

    // MARK: - metricSuggestions

    func testMetricSuggestions_containsSkillName() {
        let prompt = PromptTemplates.metricSuggestions(skill: "Piano", level: "Beginner")
        XCTAssertTrue(prompt.contains("Piano"), "Prompt should contain the skill name")
    }

    func testMetricSuggestions_containsLevel() {
        let prompt = PromptTemplates.metricSuggestions(skill: "Piano", level: "Intermediate")
        XCTAssertTrue(prompt.contains("Intermediate"), "Prompt should contain the level")
    }

    func testMetricSuggestions_containsJSONSchema() {
        let prompt = PromptTemplates.metricSuggestions(skill: "X", level: "Y")
        XCTAssertTrue(prompt.contains("\"metrics\""), "Prompt should include metrics key")
        XCTAssertTrue(prompt.contains("\"isHigherBetter\""), "Prompt should include isHigherBetter key")
        XCTAssertTrue(prompt.contains("\"unit\""), "Prompt should include unit key")
    }

    // MARK: - System Prompt

    func testMetricSuggestionsSystem_instructsJSONOnly() {
        let system = PromptTemplates.metricSuggestionsSystem
        XCTAssertTrue(system.lowercased().contains("json"), "System prompt should mention JSON")
    }

    // MARK: - MetricSuggestionResponse decoding

    func testDecode_validJSON_succeeds() throws {
        let json = """
        {
          "metrics": [
            {"name": "Words per minute", "unit": "wpm", "isHigherBetter": true},
            {"name": "Error rate", "unit": "%", "isHigherBetter": false}
          ]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let result = try JSONDecoder().decode(MetricSuggestionResponse.self, from: data)

        XCTAssertEqual(result.metrics.count, 2)
        XCTAssertEqual(result.metrics[0].name, "Words per minute")
        XCTAssertEqual(result.metrics[0].unit, "wpm")
        XCTAssertTrue(result.metrics[0].isHigherBetter)
        XCTAssertFalse(result.metrics[1].isHigherBetter)
    }

    func testDecode_missingMetricsKey_throws() throws {
        let json = """
        {"something_else": "value"}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        XCTAssertThrowsError(try JSONDecoder().decode(MetricSuggestionResponse.self, from: data))
    }

    func testDecode_extraFields_succeeds() throws {
        // Claude may include extra fields — decoder should be lenient
        let json = """
        {
          "metrics": [
            {"name": "Accuracy", "unit": "%", "isHigherBetter": true, "reasoning": "extra field"}
          ],
          "someUnexpectedTopLevelKey": "value"
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let result = try JSONDecoder().decode(MetricSuggestionResponse.self, from: data)
        XCTAssertEqual(result.metrics.count, 1)
    }

    // MARK: - SuggestedMetric -> CustomMetric conversion

    func testToCustomMetric_mapsNameUnitAndDirection() {
        let suggestion = SuggestedMetric.stub(name: "Accuracy", unit: "%", isHigherBetter: true)
        let metric = suggestion.toCustomMetric()
        XCTAssertEqual(metric.name, "Accuracy")
        XCTAssertEqual(metric.unit, "%")
        XCTAssertTrue(metric.isHigherBetter)
    }

    func testToCustomMetric_lowerIsBetter() {
        let suggestion = SuggestedMetric.stub(name: "Error rate", unit: "%", isHigherBetter: false)
        let metric = suggestion.toCustomMetric()
        XCTAssertFalse(metric.isHigherBetter)
    }
}
