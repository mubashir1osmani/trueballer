import XCTest

final class AccountFlowTests: XCTestCase {
    /// The sign-in sheet must stay up until the student signs in or closes it.
    @MainActor
    func testSignInSheetStaysOpenFromSettings() {
        let app = XCUIApplication()
        app.launchEnvironment["INITIAL_TAB"] = "today"
        app.launch()
        app.buttons["settings.open"].tap()
        let signIn = app.buttons["account.signin"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 5))
        signIn.tap()

        let google = app.buttons["signin.google"]
        XCTAssertTrue(google.waitForExistence(timeout: 5))
        // Give any competing presentation time to knock the sheet down.
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(google.isHittable, "Sign-in sheet was dismissed on its own")

        app.buttons["Close"].tap()
        XCTAssertTrue(signIn.waitForExistence(timeout: 5))
    }
}

extension AccountFlowTests {
    /// Tapping Google must open the system sign-in sheet, not crash.
    @MainActor
    func testGoogleSignInOpensWithoutCrashing() {
        let app = XCUIApplication()
        app.launchEnvironment["INITIAL_TAB"] = "today"
        app.launch()
        app.buttons["settings.open"].tap()
        let signIn = app.buttons["account.signin"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 5))
        signIn.tap()
        let google = app.buttons["signin.google"]
        XCTAssertTrue(google.waitForExistence(timeout: 5))
        google.tap()

        // iOS asks before handing off to the browser sheet.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let proceed = springboard.buttons["Continue"]
        if proceed.waitForExistence(timeout: 5) { proceed.tap() }

        Thread.sleep(forTimeInterval: 3)
        XCTAssertEqual(app.state, .runningForeground, "App crashed or left the foreground after tapping Google")
    }
}

extension AccountFlowTests {
    /// Closing Google's sheet resumes the same completion path as a real
    /// sign-in. The app must survive it and keep the sign-in screen up.
    @MainActor
    func testCancellingGoogleSignInReturnsToApp() {
        let app = XCUIApplication()
        app.launchEnvironment["INITIAL_TAB"] = "today"
        app.launch()
        app.buttons["settings.open"].tap()
        let signIn = app.buttons["account.signin"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 5))
        signIn.tap()
        let google = app.buttons["signin.google"]
        XCTAssertTrue(google.waitForExistence(timeout: 5))
        google.tap()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let proceed = springboard.buttons["Continue"]
        if proceed.waitForExistence(timeout: 5) { proceed.tap() }

        // The web sheet runs in another process; its Cancel lives there.
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), "Google sheet never appeared")
        cancel.tap()

        XCTAssertTrue(google.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(app.state, .runningForeground, "App crashed after the Google sheet closed")
    }
}
