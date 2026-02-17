import XCTest
@testable import Sage

final class SkillGoalTests: XCTestCase {

    // MARK: - Initialization

    func testInit_defaultValues() {
        let goal = SkillGoal(skillName: "Cooking")

        XCTAssertNil(goal.id)
        XCTAssertEqual(goal.skillName, "Cooking")
        XCTAssertNil(goal.skillDescription)
        XCTAssertNil(goal.skillCategory)
        XCTAssertNil(goal.currentLevel)
        XCTAssertNil(goal.targetLevel)
        XCTAssertTrue(goal.customMetrics.isEmpty)
    }

    // MARK: - JSON serialization of customMetrics

    func testCustomMetricsJSON_emptyArray() throws {
        let goal = SkillGoal(skillName: "Empty")
        let json = try goal.customMetricsJSON()
        XCTAssertEqual(json, "[]")
    }

    func testCustomMetricsJSON_roundTrip() throws {
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

        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded.first?.id, "test-id")
        XCTAssertEqual(decoded.first?.name, "Words per minute")
        XCTAssertEqual(decoded.first?.unit, "wpm")
        XCTAssertEqual(decoded.first?.targetValue, 80)
        XCTAssertEqual(decoded.first?.currentValue, 60)
        XCTAssertTrue(decoded.first?.isHigherBetter ?? false)
    }

    func testCustomMetricsJSON_multipleMetrics() throws {
        let metrics = [
            CustomMetric(name: "Speed", unit: "mph", targetValue: 30),
            CustomMetric(name: "Distance", unit: "miles", targetValue: 10),
        ]
        let goal = SkillGoal(skillName: "Cycling", customMetrics: metrics)

        let json = try goal.customMetricsJSON()
        let decoded = try SkillGoal.decodeMetrics(from: json)

        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].name, "Speed")
        XCTAssertEqual(decoded[1].name, "Distance")
    }

    func testDecodeMetrics_invalidJSON_throws() {
        XCTAssertThrowsError(try SkillGoal.decodeMetrics(from: "not json"))
    }

    // MARK: - CustomMetric

    func testCustomMetric_defaultID_isUnique() {
        let a = CustomMetric(name: "A", unit: "u")
        let b = CustomMetric(name: "B", unit: "u")
        XCTAssertNotEqual(a.id, b.id)
    }

    func testCustomMetric_optionalValues_nilByDefault() {
        let metric = CustomMetric(name: "Reps", unit: "count")
        XCTAssertNil(metric.targetValue)
        XCTAssertNil(metric.currentValue)
    }

    // MARK: - Equatable

    func testSkillGoal_equatable() {
        let a = SkillGoal(skillName: "Swimming")
        var b = a
        XCTAssertEqual(a, b)

        b.skillName = "Running"
        XCTAssertNotEqual(a, b)
    }
}
