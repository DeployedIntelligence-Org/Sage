import XCTest
@testable import Sage

@MainActor
final class OnboardingViewModelTests: XCTestCase {

    // MARK: - Helpers

    /// Creates an isolated DatabaseService backed by a temp file.
    private func makeTempDB() throws -> (DatabaseService, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("test.db")
        let db = DatabaseService(url: url)
        try db.open()
        return (db, dir)
    }

    // MARK: - Progress

    func testProgress_onFirstStep_isOneThird() {
        let vm = OnboardingViewModel()
        XCTAssertEqual(vm.progress, 1.0 / 3.0, accuracy: 0.001)
    }

    func testProgress_advancesToSecondStep() {
        let vm = OnboardingViewModel()
        vm.skillName = "Guitar"
        vm.advance()
        XCTAssertEqual(vm.currentStep, .levelSelection)
        XCTAssertEqual(vm.progress, 2.0 / 3.0, accuracy: 0.001)
    }

    // MARK: - Step Validation

    func testIsCurrentStepValid_skillInput_falseWhenEmpty() {
        let vm = OnboardingViewModel()
        vm.skillName = ""
        XCTAssertFalse(vm.isCurrentStepValid)
    }

    func testIsCurrentStepValid_skillInput_falseWhenWhitespaceOnly() {
        let vm = OnboardingViewModel()
        vm.skillName = "   "
        XCTAssertFalse(vm.isCurrentStepValid)
    }

    func testIsCurrentStepValid_skillInput_trueWhenNonEmpty() {
        let vm = OnboardingViewModel()
        vm.skillName = "Piano"
        XCTAssertTrue(vm.isCurrentStepValid)
    }

    func testIsCurrentStepValid_levelSelection_requiresBothLevels() {
        let vm = OnboardingViewModel()
        vm.skillName = "Piano"
        vm.advance() // move to levelSelection

        vm.currentLevel = "Beginner"
        vm.targetLevel = ""
        XCTAssertFalse(vm.isCurrentStepValid)

        vm.currentLevel = ""
        vm.targetLevel = "Advanced"
        XCTAssertFalse(vm.isCurrentStepValid)

        vm.currentLevel = "Beginner"
        vm.targetLevel = "Advanced"
        XCTAssertTrue(vm.isCurrentStepValid)
    }

    func testIsCurrentStepValid_metricSelection_alwaysTrue() {
        let vm = OnboardingViewModel()
        vm.skillName = "Piano"
        vm.advance()
        vm.currentLevel = "Beginner"
        vm.targetLevel = "Advanced"
        vm.advance() // move to metricSelection
        XCTAssertTrue(vm.isCurrentStepValid)
    }

    // MARK: - Navigation

    func testAdvance_doesNotMoveForwardWhenStepInvalid() {
        let vm = OnboardingViewModel()
        vm.skillName = ""
        vm.advance()
        XCTAssertEqual(vm.currentStep, .skillInput)
    }

    func testGoBack_fromLevelSelection_returnsToSkillInput() {
        let vm = OnboardingViewModel()
        vm.skillName = "Guitar"
        vm.advance()
        vm.goBack()
        XCTAssertEqual(vm.currentStep, .skillInput)
    }

    func testGoBack_onFirstStep_doesNothing() {
        let vm = OnboardingViewModel()
        vm.goBack()
        XCTAssertEqual(vm.currentStep, .skillInput)
    }

    // MARK: - Metric Management

    func testIsNewMetricValid_falseWhenNameEmpty() {
        let vm = OnboardingViewModel()
        vm.newMetricName = ""
        vm.newMetricUnit = "wpm"
        XCTAssertFalse(vm.isNewMetricValid)
    }

    func testIsNewMetricValid_falseWhenUnitEmpty() {
        let vm = OnboardingViewModel()
        vm.newMetricName = "Speed"
        vm.newMetricUnit = ""
        XCTAssertFalse(vm.isNewMetricValid)
    }

    func testIsNewMetricValid_trueWhenBothFilled() {
        let vm = OnboardingViewModel()
        vm.newMetricName = "Speed"
        vm.newMetricUnit = "wpm"
        XCTAssertTrue(vm.isNewMetricValid)
    }

    func testAddMetric_appendsToList() {
        let vm = OnboardingViewModel()
        vm.newMetricName = "Speed"
        vm.newMetricUnit = "wpm"
        vm.addMetric()
        XCTAssertEqual(vm.metrics.count, 1)
        XCTAssertEqual(vm.metrics.first?.name, "Speed")
        XCTAssertEqual(vm.metrics.first?.unit, "wpm")
    }

    func testAddMetric_clearsDraftAfterAdd() {
        let vm = OnboardingViewModel()
        vm.newMetricName = "Speed"
        vm.newMetricUnit = "wpm"
        vm.addMetric()
        XCTAssertTrue(vm.newMetricName.isEmpty)
        XCTAssertTrue(vm.newMetricUnit.isEmpty)
        XCTAssertTrue(vm.newMetricIsHigherBetter) // reset to default
    }

    func testAddMetric_doesNothingWhenInvalid() {
        let vm = OnboardingViewModel()
        vm.newMetricName = ""
        vm.newMetricUnit = "wpm"
        vm.addMetric()
        XCTAssertTrue(vm.metrics.isEmpty)
    }

    func testRemoveMetric_removesAtOffset() {
        let vm = OnboardingViewModel()
        vm.newMetricName = "Speed"; vm.newMetricUnit = "wpm"; vm.addMetric()
        vm.newMetricName = "Accuracy"; vm.newMetricUnit = "%"; vm.addMetric()
        vm.removeMetric(at: IndexSet(integer: 0))
        XCTAssertEqual(vm.metrics.count, 1)
        XCTAssertEqual(vm.metrics.first?.name, "Accuracy")
    }

    // MARK: - Suggestion Toggle

    func testToggleSuggestion_selectsAndDeselects() {
        let vm = OnboardingViewModel()
        let suggestion = SuggestedMetric.stub(name: "Words per minute")
        vm.suggestedMetrics = [suggestion]

        XCTAssertFalse(vm.isSelected(suggestion))

        vm.toggleSuggestion(suggestion)
        XCTAssertTrue(vm.isSelected(suggestion))

        vm.toggleSuggestion(suggestion)
        XCTAssertFalse(vm.isSelected(suggestion))
    }

    func testIsSelected_falseForUnknownSuggestion() {
        let vm = OnboardingViewModel()
        let suggestion = SuggestedMetric.stub(name: "Pages read")
        XCTAssertFalse(vm.isSelected(suggestion))
    }

    // MARK: - buildSkillGoal

    func testBuildSkillGoal_mapsFormFieldsCorrectly() {
        let vm = OnboardingViewModel()
        vm.skillName = "  Guitar  "
        vm.skillDescription = "Fingerpicking"
        vm.skillCategory = "Music"
        vm.currentLevel = "Beginner"
        vm.targetLevel = "Intermediate"

        let goal = vm.buildSkillGoal()

        XCTAssertEqual(goal.skillName, "Guitar")
        XCTAssertEqual(goal.skillDescription, "Fingerpicking")
        XCTAssertEqual(goal.skillCategory, "Music")
        XCTAssertEqual(goal.currentLevel, "Beginner")
        XCTAssertEqual(goal.targetLevel, "Intermediate")
    }

    func testBuildSkillGoal_nilsEmptyOptionalFields() {
        let vm = OnboardingViewModel()
        vm.skillName = "Guitar"
        vm.skillDescription = "   "
        vm.skillCategory = ""

        let goal = vm.buildSkillGoal()

        XCTAssertNil(goal.skillDescription)
        XCTAssertNil(goal.skillCategory)
        XCTAssertNil(goal.currentLevel)
        XCTAssertNil(goal.targetLevel)
    }

    // MARK: - saveSkillGoal

    func testSaveSkillGoal_persistsGoalWithSelectedAndManualMetrics() throws {
        let (db, tempDir) = try makeTempDB()
        defer {
            db.close()
            try? FileManager.default.removeItem(at: tempDir)
        }

        let vm = OnboardingViewModel(databaseService: db)
        vm.skillName = "Typing"
        vm.currentLevel = "Beginner"
        vm.targetLevel = "Advanced"

        // AI suggestion (pre-selected)
        let suggestion = SuggestedMetric.stub(name: "WPM")
        vm.suggestedMetrics = [suggestion]
        vm.selectedMetrics = [suggestion.id]

        // Manual metric
        vm.newMetricName = "Accuracy"
        vm.newMetricUnit = "%"
        vm.addMetric()

        let success = vm.saveSkillGoal()

        XCTAssertTrue(success)
        XCTAssertTrue(vm.isComplete)

        let saved = try db.fetchAll()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved[0].skillName, "Typing")
        // Should have both selected suggestion + manual metric
        XCTAssertEqual(saved[0].customMetrics.count, 2)
        let names = saved[0].customMetrics.map { $0.name }
        XCTAssertTrue(names.contains("WPM"))
        XCTAssertTrue(names.contains("Accuracy"))
    }

    func testSaveSkillGoal_onlyDeselectedSuggestionsAreExcluded() throws {
        let (db, tempDir) = try makeTempDB()
        defer {
            db.close()
            try? FileManager.default.removeItem(at: tempDir)
        }

        let vm = OnboardingViewModel(databaseService: db)
        vm.skillName = "Chess"
        vm.currentLevel = "Beginner"
        vm.targetLevel = "Expert"

        let s1 = SuggestedMetric.stub(name: "Elo rating")
        let s2 = SuggestedMetric.stub(name: "Puzzles solved")
        vm.suggestedMetrics = [s1, s2]
        // Only select s1
        vm.selectedMetrics = [s1.id]

        let success = vm.saveSkillGoal()
        XCTAssertTrue(success)

        let saved = try db.fetchAll()
        let names = saved[0].customMetrics.map { $0.name }
        XCTAssertTrue(names.contains("Elo rating"))
        XCTAssertFalse(names.contains("Puzzles solved"))
    }

    func testSaveSkillGoal_setsIsComplete() throws {
        let (db, tempDir) = try makeTempDB()
        defer {
            db.close()
            try? FileManager.default.removeItem(at: tempDir)
        }

        let vm = OnboardingViewModel(databaseService: db)
        vm.skillName = "Running"
        vm.currentLevel = "Beginner"
        vm.targetLevel = "Advanced"

        XCTAssertFalse(vm.isComplete)
        vm.saveSkillGoal()
        XCTAssertTrue(vm.isComplete)
    }
}

// MARK: - Test Doubles

extension SuggestedMetric {
    /// Constructs a `SuggestedMetric` suitable for use in unit tests.
    static func stub(name: String, unit: String = "units") -> SuggestedMetric {
        let json = """
        {"name": "\(name)", "type": "count", "unit": "\(unit)"}
        """
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(SuggestedMetric.self, from: Data(json.utf8))
    }
}
