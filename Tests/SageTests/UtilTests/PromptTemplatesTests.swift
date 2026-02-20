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

    // MARK: - coachSystem

    func testCoachSystem_containsSkillName() {
        let prompt = PromptTemplates.coachSystem(
            skillName: "Piano",
            currentLevel: nil,
            targetLevel: nil,
            metrics: []
        )
        XCTAssertTrue(prompt.contains("Piano"), "System prompt should contain the skill name")
    }

    func testCoachSystem_containsCurrentAndTargetLevel() {
        let prompt = PromptTemplates.coachSystem(
            skillName: "Chess",
            currentLevel: "Beginner",
            targetLevel: "Intermediate",
            metrics: []
        )
        XCTAssertTrue(prompt.contains("Beginner"),     "Prompt should include current level")
        XCTAssertTrue(prompt.contains("Intermediate"), "Prompt should include target level")
    }

    func testCoachSystem_currentLevelOnly_doesNotMentionTarget() {
        let prompt = PromptTemplates.coachSystem(
            skillName: "Guitar",
            currentLevel: "Beginner",
            targetLevel: nil,
            metrics: []
        )
        XCTAssertTrue(prompt.contains("Beginner"))
        // "wants to reach" phrasing only appears when both levels are present.
        XCTAssertFalse(prompt.contains("wants to reach"))
    }

    func testCoachSystem_noLevels_omitsLevelContext() {
        let prompt = PromptTemplates.coachSystem(
            skillName: "Drawing",
            currentLevel: nil,
            targetLevel: nil,
            metrics: []
        )
        XCTAssertFalse(prompt.contains("level and wants"))
    }

    func testCoachSystem_withMetrics_listsMetricNames() {
        let metrics = [
            CustomMetric(name: "Scales per minute", unit: "spm", isHigherBetter: true),
            CustomMetric(name: "Error rate",         unit: "%",   isHigherBetter: false),
        ]
        let prompt = PromptTemplates.coachSystem(
            skillName: "Piano",
            currentLevel: nil,
            targetLevel: nil,
            metrics: metrics
        )
        XCTAssertTrue(prompt.contains("Scales per minute"), "Prompt should list metric names")
        XCTAssertTrue(prompt.contains("Error rate"),         "Prompt should list all metrics")
        XCTAssertTrue(prompt.contains("spm"),                "Prompt should include units")
    }

    func testCoachSystem_noMetrics_omitsMetricsSection() {
        let prompt = PromptTemplates.coachSystem(
            skillName: "Yoga",
            currentLevel: nil,
            targetLevel: nil,
            metrics: []
        )
        XCTAssertFalse(prompt.contains("track the following metrics"))
    }

    func testCoachSystem_isNonEmpty() {
        let prompt = PromptTemplates.coachSystem(
            skillName: "Coding",
            currentLevel: "Junior",
            targetLevel: "Senior",
            metrics: [CustomMetric(name: "PRs merged", unit: "PRs", isHigherBetter: true)]
        )
        XCTAssertFalse(prompt.isEmpty)
    }

    func testCoachSystem_withRecentSessions_includesSectionHeader() {
        let session = PracticeSession(
            skillGoalId: 1,
            durationMinutes: 30,
            notes: "Worked on arpeggios",
            metricEntries: [MetricEntry(metricName: "BPM", value: 80, unit: "bpm")]
        )
        let prompt = PromptTemplates.coachSystem(
            skillName: "Piano",
            currentLevel: nil,
            targetLevel: nil,
            metrics: [],
            recentSessions: [session]
        )
        XCTAssertTrue(prompt.contains("Recent practice sessions"), "Should include sessions header")
        XCTAssertTrue(prompt.contains("30 min"), "Should include session duration")
        XCTAssertTrue(prompt.contains("BPM: 80 bpm"), "Should include metric entry")
        XCTAssertTrue(prompt.contains("Worked on arpeggios"), "Should include notes")
    }

    func testCoachSystem_withNoRecentSessions_omitsSessionsSection() {
        let prompt = PromptTemplates.coachSystem(
            skillName: "Guitar",
            currentLevel: nil,
            targetLevel: nil,
            metrics: [],
            recentSessions: []
        )
        XCTAssertFalse(prompt.contains("Recent practice sessions"))
    }

    func testCoachSystem_capsSessionsAtFive() {
        let sessions = (1...10).map { i in
            PracticeSession(skillGoalId: 1, durationMinutes: i * 10)
        }
        let prompt = PromptTemplates.coachSystem(
            skillName: "Yoga",
            currentLevel: nil,
            targetLevel: nil,
            metrics: [],
            recentSessions: sessions
        )
        // Only the first 5 sessions should appear; count bullet points
        let bulletCount = prompt.components(separatedBy: "\n- ").count - 1
        XCTAssertEqual(bulletCount, 5, "Should cap at 5 recent sessions")
    }

    // MARK: - conversationTitle

    func testConversationTitleUser_containsFirstMessage() {
        let prompt = PromptTemplates.conversationTitleUser(firstMessage: "How do I improve my bowing technique?")
        XCTAssertTrue(prompt.contains("How do I improve my bowing technique?"))
    }

    func testConversationTitleSystem_mentionsShortTitle() {
        let system = PromptTemplates.conversationTitleSystem
        XCTAssertTrue(system.lowercased().contains("title"), "System prompt should mention title")
    }
}
