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
        XCTAssertTrue(prompt.contains("\"metrics\""), "Prompt should include JSON schema hint")
        XCTAssertTrue(prompt.contains("\"reasoning\""), "Prompt should include reasoning key")
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
            {"name": "Words per minute", "type": "count", "unit": "wpm"},
            {"name": "Practice time", "type": "duration", "unit": "minutes"}
          ],
          "reasoning": "These capture speed and consistency."
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let result = try JSONDecoder().decode(MetricSuggestionResponse.self, from: data)

        XCTAssertEqual(result.metrics.count, 2)
        XCTAssertEqual(result.metrics[0].name, "Words per minute")
        XCTAssertEqual(result.metrics[0].type, .count)
        XCTAssertEqual(result.metrics[1].unit, "minutes")
        XCTAssertFalse(result.reasoning.isEmpty)
    }

    func testDecode_unknownMetricType_throws() throws {
        let json = """
        {
          "metrics": [{"name": "Foo", "type": "something_new", "unit": "units"}],
          "reasoning": "Test"
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        XCTAssertThrowsError(try JSONDecoder().decode(MetricSuggestionResponse.self, from: data))
    }

    // MARK: - SuggestedMetric -> CustomMetric conversion

    func testToCustomMetric_mapsNameAndUnit() {
        let suggestion = SuggestedMetric(name: "Accuracy", type: .rating, unit: "%")
        let metric = suggestion.toCustomMetric()
        XCTAssertEqual(metric.name, "Accuracy")
        XCTAssertEqual(metric.unit, "%")
    }
}
