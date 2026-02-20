import XCTest

/// UI tests for the onboarding multi-step form.
///
/// These tests drive the app through the complete onboarding flow and verify
/// that each step's validation and navigation behave correctly.
final class OnboardingUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Step 1: Skill Input

    func testNextDisabledWhenSkillNameEmpty() {
        let nextButton = app.buttons["Next"]
        XCTAssertTrue(nextButton.exists)
        XCTAssertFalse(nextButton.isEnabled, "Next should be disabled when skill name is empty")
    }

    func testNextEnabledAfterSkillNameEntered() {
        let skillNameField = app.textFields["e.g. Fingerpicking Guitar"]
        skillNameField.tap()
        skillNameField.typeText("Watercolor Painting")

        let nextButton = app.buttons["Next"]
        XCTAssertTrue(nextButton.isEnabled, "Next should be enabled after entering a skill name")
    }

    func testAdvanceToStepTwo() {
        enterSkillName("Guitar Fingerpicking")
        app.buttons["Next"].tap()

        // Step 2 heading should appear
        XCTAssertTrue(
            app.staticTexts["Where are you starting from?"].waitForExistence(timeout: 2),
            "Should navigate to step 2 after valid step 1"
        )
    }

    // MARK: - Step 2: Level Selection

    func testNextDisabledWhenLevelsNotSelected() {
        advanceToStepTwo()
        XCTAssertFalse(
            app.buttons["Next"].isEnabled,
            "Next should be disabled when no levels are selected"
        )
    }

    func testNextEnabledAfterBothLevelsSelected() {
        advanceToStepTwo()
        selectCurrentLevel("Beginner")
        selectTargetLevel("Advanced")

        XCTAssertTrue(
            app.buttons["Next"].isEnabled,
            "Next should be enabled after both levels are selected"
        )
    }

    func testBackNavigationFromStepTwo() {
        advanceToStepTwo()
        app.buttons["Back"].tap()

        XCTAssertTrue(
            app.staticTexts["What skill do you want to master?"].waitForExistence(timeout: 2),
            "Back button should return to step 1"
        )
    }

    // MARK: - Step 3: Metric Selection

    func testAdvanceToStepThree() {
        advanceToStepThree()
        XCTAssertTrue(
            app.staticTexts["How will you measure progress?"].waitForExistence(timeout: 2),
            "Should navigate to step 3 after valid step 2"
        )
    }

    func testFinishEnabledWithoutMetrics() {
        advanceToStepThree()
        XCTAssertTrue(
            app.buttons["Finish"].isEnabled,
            "Finish should be enabled even with no metrics (optional step)"
        )
    }

    func testAddMetricEnablesAddButton() {
        advanceToStepThree()

        let nameField = app.textFields["Name (e.g. Speed)"]
        nameField.ensureVisible(in: app)
        nameField.tap()
        nameField.typeText("Words per minute")

        let unitField = app.textFields["Unit (e.g. wpm)"]
        unitField.ensureVisible(in: app)
        unitField.tap()
        // On macOS, hasKeyboardFocus can be unreliable; rely on hittable and retry typing.
        unitField.typeTextReliably("wpm")

        XCTAssertTrue(
            app.buttons["Add"].isEnabled,
            "Add button should be enabled when name and unit are filled"
        )
    }

    func testAddMetricAppearsInList() {
        advanceToStepThree()
        addMetric(name: "Words per minute", unit: "wpm")

        XCTAssertTrue(
            app.staticTexts["Words per minute"].waitForExistence(timeout: 2),
            "Added metric should appear in the list"
        )
    }

    func testCompleteOnboardingFlow() {
        enterSkillName("Piano")
        app.buttons["Next"].tap()

        selectCurrentLevel("Beginner")
        selectTargetLevel("Intermediate")
        app.buttons["Next"].tap()

        app.buttons["Finish"].tap()

        XCTAssertTrue(
            app.staticTexts["You're all set!"].waitForExistence(timeout: 3),
            "Completion screen should appear after finishing onboarding"
        )
    }

    // MARK: - Helpers

    private func enterSkillName(_ name: String) {
        let field = app.textFields["e.g. Fingerpicking Guitar"]
        field.ensureVisible(in: app)
        field.tap()
        field.typeText(name)
    }

    private func advanceToStepTwo() {
        enterSkillName("Test Skill")
        app.buttons["Next"].tap()
        _ = app.staticTexts["Where are you starting from?"].waitForExistence(timeout: 2)
    }

    private func selectCurrentLevel(_ level: String) {
        app.buttons.matching(identifier: "current-\(level)").firstMatch.tap()
    }

    private func selectTargetLevel(_ level: String) {
        app.buttons.matching(identifier: "target-\(level)").firstMatch.tap()
    }

    private func advanceToStepThree() {
        advanceToStepTwo()
        selectCurrentLevel("Beginner")
        selectTargetLevel("Advanced")
        app.buttons["Next"].tap()
        _ = app.staticTexts["How will you measure progress?"].waitForExistence(timeout: 2)
    }

    private func addMetric(name: String, unit: String) {
        let nameField = app.textFields["Name (e.g. Speed)"]
        nameField.ensureVisible(in: app)
        nameField.tap()
        nameField.typeText(name)

        let unitField = app.textFields["Unit (e.g. wpm)"]
        unitField.ensureVisible(in: app)
        unitField.tap()
        unitField.typeTextReliably(unit)

        app.buttons["Add"].tap()
    }
}

private extension XCUIElement {
    // Scroll the element into view if it’s inside a scroll view.
    func ensureVisible(in app: XCUIApplication, timeout: TimeInterval = 2.0) {
        if !isHittable {
            app.swipeUp()
            _ = waitForExistence(timeout: timeout)
        }
    }

    // Retry typing a short string to mitigate occasional focus issues on macOS.
    func typeTextReliably(_ text: String, attempts: Int = 2) {
        for i in 0..<attempts {
            if i > 0 { tap() }
            typeText(text)
            // If value already contains the typed text, stop early.
            // value is Any?; cast to String if possible.
            if let v = self.value as? String, v.contains(text) { break }
        }
    }
}

