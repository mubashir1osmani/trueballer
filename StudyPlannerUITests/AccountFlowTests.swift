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
