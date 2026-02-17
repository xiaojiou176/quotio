import XCTest

final class QuotioUITestsLaunchTests: XCTestCase {
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchPerformance() throws {
        let app = XCUIApplication()
        app.launchEnvironment["QUOTIO_UI_TEST_MODE"] = "1"
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            app.launch()
        }
    }
}
