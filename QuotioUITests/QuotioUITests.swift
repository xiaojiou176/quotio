import XCTest

final class QuotioUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunchesAndShowsMainWindow() throws {
        let app = XCUIApplication()
        app.launchEnvironment["QUOTIO_UI_TEST_MODE"] = "1"
        app.launch()
        XCTAssertTrue(app.otherElements["ui-test-harness-root"].waitForExistence(timeout: 10))
    }
}
