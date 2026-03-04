import XCTest

final class QuotioUITestsLaunchTests: XCTestCase {
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    // assertion-quality:allow-assertionless - XCTest measure() validates launch performance without XCTAssert.
    func testLaunchPerformance() throws {
        let app = XCUIApplication()
        app.launchEnvironment["QUOTIO_UI_TEST_MODE"] = "1"
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            app.launch()
        }
    }
}
