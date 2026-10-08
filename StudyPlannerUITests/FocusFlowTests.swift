import XCTest

final class FocusFlowTests: XCTestCase {
    @MainActor
    func testTodayFocusPauseRelaunchAndComplete() throws {
        let app = XCUIApplication()
        app.launchEnvironment["INITIAL_TAB"] = "today"
        app.launch()
        let title = "Focus check \(Int(Date().timeIntervalSince1970))"
        app.buttons["Add task"].tap()
        let field = app.textFields["What's due?"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        // The field is auto-focused. Wait for the keyboard and handle iOS's
        // first-use keyboard introduction on a fresh simulator.
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        if app.buttons["Continue"].exists { app.buttons["Continue"].tap() }
        field.typeText(title)
        app.navigationBars["New Task"].buttons["Add"].tap()
        let focusButton = app.buttons["Focus on \(title)"]
        if !focusButton.isHittable { app.swipeUp() }
        XCTAssertTrue(focusButton.waitForExistence(timeout: 5))
        focusButton.tap()
        app.buttons["focus.start"].tap()
        XCTAssertTrue(app.buttons["focus.pause"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["focus.status"].label, "Focusing")
        app.buttons["focus.pause"].tap()
        XCTAssertEqual(app.staticTexts["focus.status"].label, "Paused")
        let pausedTime = app.staticTexts["focus.elapsed"].label
        app.terminate()
        app.launchEnvironment["INITIAL_TAB"] = "focus"
        app.launch()
        XCTAssertTrue(app.buttons["focus.pause"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["focus.status"].label, "Paused")
        XCTAssertEqual(app.staticTexts["focus.elapsed"].label, pausedTime)
        app.buttons["focus.pause"].tap()
        XCTAssertEqual(app.staticTexts["focus.status"].label, "Focusing")

        // Leaving the app exercises the system-rendered timer in Dynamic Island.
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let homeScreenshot = XCTAttachment(screenshot: springboard.screenshot())
        homeScreenshot.name = "Focus Live Activity on Home Screen"
        homeScreenshot.lifetime = .keepAlways
        add(homeScreenshot)
        app.activate()
        XCTAssertTrue(app.buttons["focus.complete"].waitForExistence(timeout: 5))
        let focusScreenshot = XCTAttachment(screenshot: app.screenshot())
        focusScreenshot.name = "Running Focus session"
        focusScreenshot.lifetime = .keepAlways
        add(focusScreenshot)
        app.buttons["focus.complete"].tap()
        XCTAssertTrue(app.staticTexts["Task completed"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["focus.pause"].exists)
        app.buttons["tab.today"].tap()
        XCTAssertFalse(app.buttons["Focus on \(title)"].exists)
        app.buttons["tab.focus"].tap()
        XCTAssertTrue(app.staticTexts[title].exists)
        let historyScreenshot = XCTAttachment(screenshot: app.screenshot())
        historyScreenshot.name = "Logged focus time"
        historyScreenshot.lifetime = .keepAlways
        add(historyScreenshot)
    }
}
