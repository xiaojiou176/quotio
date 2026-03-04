import XCTest

final class QuotioUITests: XCTestCase {
    private func launchHarnessApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["QUOTIO_UI_TEST_MODE"] = "1"
        app.launch()
        return app
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunchesAndShowsMainWindow() throws {
        let app = launchHarnessApp()
        XCTAssertTrue(app.otherElements["ui-test-harness-root"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testUITestHarnessShowsKeyPageAnchors() throws {
        let app = launchHarnessApp()

        XCTAssertTrue(app.staticTexts["ui-test-harness-title"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["ui-test-keypage-dashboard"].exists)
        XCTAssertTrue(app.staticTexts["ui-test-keypage-apikeys"].exists)
        XCTAssertTrue(app.staticTexts["ui-test-keypage-logs"].exists)
    }

    @MainActor
    func testUITestHarnessCanSwitchSelectedPageToLogs() throws {
        let app = launchHarnessApp()

        let selectedPage = app.staticTexts["ui-test-selected-page"]
        XCTAssertTrue(selectedPage.waitForExistence(timeout: 10))
        XCTAssertEqual(selectedPage.value as? String, "dashboard")

        let logsButton = app.buttons["ui-test-tab-logs"]
        XCTAssertTrue(logsButton.waitForExistence(timeout: 10))
        XCTAssertEqual(logsButton.value as? String, "0")
        logsButton.click()

        XCTAssertEqual(selectedPage.value as? String, "logs")
        XCTAssertEqual(logsButton.value as? String, "1")
    }

    @MainActor
    func testUITestHarnessTabSwitchShowsPageStateForAPIKeys() throws {
        let app = launchHarnessApp()

        let selectedPage = app.staticTexts["ui-test-selected-page"]
        XCTAssertTrue(selectedPage.waitForExistence(timeout: 10))

        let apiKeysButton = app.buttons["ui-test-tab-apikeys"]
        XCTAssertTrue(apiKeysButton.waitForExistence(timeout: 10))
        apiKeysButton.click()

        XCTAssertEqual(selectedPage.value as? String, "apiKeys")
        XCTAssertEqual(apiKeysButton.value as? String, "1")
    }

    @MainActor
    func testUITestHarnessTabButtonsAreAccessibleAndInteractive() throws {
        let app = launchHarnessApp()

        let dashboardButton = app.buttons["ui-test-tab-dashboard"]
        let apiKeysButton = app.buttons["ui-test-tab-apikeys"]
        let logsButton = app.buttons["ui-test-tab-logs"]

        XCTAssertTrue(dashboardButton.waitForExistence(timeout: 10))
        XCTAssertTrue(apiKeysButton.waitForExistence(timeout: 10))
        XCTAssertTrue(logsButton.waitForExistence(timeout: 10))

        XCTAssertTrue(dashboardButton.isHittable)
        XCTAssertTrue(apiKeysButton.isHittable)
        XCTAssertTrue(logsButton.isHittable)
    }
}
