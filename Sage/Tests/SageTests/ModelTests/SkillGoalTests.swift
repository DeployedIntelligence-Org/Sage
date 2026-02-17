import Testing
@testable import Sage

@Suite("SkillGoal Tests")
struct SkillGoalTests {

    // MARK: - Initialization

    @Test("Default values are correct on init")
    func defaultValues() {
        let goal = SkillGoal(skillName: "Cooking")

        #expect(goal.id == nil)
        #expect(goal.skillName == "Cooking")
        #expect(goal.skillDescription == nil)
        #expect(goal.skillCategory == nil)
        #expect(goal.currentLevel == nil)
        #expect(goal.targetLevel == nil)
        #expect(goal.customMetrics.isEmpty)
    }

    // MARK: - JSON serialization of customMetrics

    @Test("customMetricsJSON returns empty array for empty metrics")
    func customMetricsJSON_emptyArray() throws {
        let goal = SkillGoal(skillName: "Empty")
        let json = try goal.customMetricsJSON()
        #expect(json == "[]")
    }

    @Test("customMetricsJSON round-trips a single metric correctly")
    func customMetricsJSON_roundTrip() throws {
        let metric = CustomMetric(
            id: "test-id",
            name: "Words per minute",
            unit: "wpm",
            targetValue: 80,
            currentValue: 60,
            isHigherBetter: true
        )
        let goal = SkillGoal(skillName: "Typing", customMetrics: [metric])

        let json = try goal.customMetricsJSON()
        let decoded = try SkillGoal.decodeMetrics(from: json)

        #expect(decoded.count == 1)
        #expect(decoded.first?.id == "test-id")
        #expect(decoded.first?.name == "Words per minute")
        #expect(decoded.first?.unit == "wpm")
        #expect(decoded.first?.targetValue == 80)
        #expect(decoded.first?.currentValue == 60)
        #expect(decoded.first?.isHigherBetter == true)
    }

    @Test("customMetricsJSON round-trips multiple metrics correctly")
    func customMetricsJSON_multipleMetrics() throws {
        let metrics = [
            CustomMetric(name: "Speed", unit: "mph", targetValue: 30),
            CustomMetric(name: "Distance", unit: "miles", targetValue: 10),
        ]
        let goal = SkillGoal(skillName: "Cycling", customMetrics: metrics)

        let json = try goal.customMetricsJSON()
        let decoded = try SkillGoal.decodeMetrics(from: json)

        #expect(decoded.count == 2)
        #expect(decoded[0].name == "Speed")
        #expect(decoded[1].name == "Distance")
    }

    @Test("decodeMetrics throws on invalid JSON")
    func decodeMetrics_invalidJSON_throws() {
        #expect(throws: (any Error).self) {
            try SkillGoal.decodeMetrics(from: "not json")
        }
    }

    // MARK: - CustomMetric

    @Test("Default IDs for two CustomMetrics are unique")
    func customMetric_defaultID_isUnique() {
        let a = CustomMetric(name: "A", unit: "u")
        let b = CustomMetric(name: "B", unit: "u")
        #expect(a.id != b.id)
    }

    @Test("Optional CustomMetric values are nil by default")
    func customMetric_optionalValues_nilByDefault() {
        let metric = CustomMetric(name: "Reps", unit: "count")
        #expect(metric.targetValue == nil)
        #expect(metric.currentValue == nil)
    }

    // MARK: - Equatable

    @Test("SkillGoal equatability reflects value changes")
    func skillGoal_equatable() {
        let a = SkillGoal(skillName: "Swimming")
        var b = a
        #expect(a == b)

        b.skillName = "Running"
        #expect(a != b)
    }
}
