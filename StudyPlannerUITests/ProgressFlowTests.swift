import XCTest

final class ProgressFlowTests: XCTestCase {
    @MainActor
    func testGradesTargetsPersistenceAndProgress() {
        let app = XCUIApplication()
        app.launchEnvironment["INITIAL_TAB"] = "today"
        app.launch()
        openProgress(in: app)
        let name = "Biology \(Int(Date.now.timeIntervalSince1970))"
        app.buttons["Add course"].tap()
        let nameField = app.textFields["course.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap(); nameField.typeText(name)
        app.buttons["course.save"].tap()
        let row = app.buttons["progress.course.\(name)"]
        for _ in 0..<4 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        addGrade(in: app, title: "Quiz 1", percentage: "60", weight: "10")
        XCTAssertTrue(app.staticTexts["grade.average"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["grade.average"].label, "60.0%")
        XCTAssertTrue(app.staticTexts["grade.belowTarget"].exists)
        app.buttons["progress.close"].tap()
        app.navigationBars["Settings"].buttons["Done"].tap()
        let risk = app.buttons["today.course.\(name)"]
        for _ in 0..<5 where !risk.isHittable { app.swipeUp() }
        XCTAssertTrue(risk.waitForExistence(timeout: 5))
        openProgress(in: app)
        let course = app.buttons["progress.course.\(name)"]
        for _ in 0..<4 where !course.isHittable { app.swipeUp() }
        XCTAssertTrue(course.waitForExistence(timeout: 5)); course.tap()
        addGrade(in: app, title: "Lab report", percentage: "90", weight: "30")
        XCTAssertEqual(app.staticTexts["grade.average"].label, "82.5%")
        XCTAssertFalse(app.staticTexts["grade.belowTarget"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Course grades and study effort"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.terminate(); app.launch()
        openProgress(in: app)
        let restored = app.buttons["progress.course.\(name)"]
        for _ in 0..<4 where !restored.isHittable { app.swipeUp() }
        XCTAssertTrue(restored.waitForExistence(timeout: 5)); restored.tap()
        XCTAssertEqual(app.staticTexts["grade.average"].label, "82.5%")
    }

    @MainActor
    private func openProgress(in app: XCUIApplication) {
        app.buttons["settings.open"].tap()
        let progress = app.buttons["settings.progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        progress.tap()
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func addGrade(in app: XCUIApplication, title: String, percentage: String, weight: String) {
        let add = app.buttons["grade.add"]
        for _ in 0..<3 where !add.isHittable { app.swipeDown() }
        add.tap()
        let titleField = app.textFields["grade.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap(); titleField.typeText(title)
        replace(app.textFields["grade.percentage"], with: percentage)
        replace(app.textFields["grade.weight"], with: weight)
        app.buttons["grade.save"].tap()
    }

    @MainActor
    private func replace(_ field: XCUIElement, with text: String) {
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        let current = field.value as? String ?? ""
        if current.first?.isNumber == true { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count)) }
        field.typeText(text)
        XCTAssertEqual(field.value as? String, text)
    }

}
