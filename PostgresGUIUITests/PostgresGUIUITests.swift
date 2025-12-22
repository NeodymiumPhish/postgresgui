import XCTest

final class PostgresGUIUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testAppOpens() throws {
        // Verify the app launched successfully
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5.0))
    }
}
