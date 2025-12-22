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

    /// Test that opening the connection form works from either the welcome screen or the sidebar.
    /// - If on welcome screen: clicks "Connect to Server" button
    /// - If not on welcome screen: clicks the plus button next to the settings icon in the sidebar
    func testOpenConnectionForm() throws {
        let welcomeText = app.staticTexts["welcomeText"]

        if welcomeText.waitForExistence(timeout: 2) {
            // On welcome screen - click "Connect to Server" button
            let connectToServerButton = app.buttons["connectToServerButton"]
            XCTAssertTrue(connectToServerButton.exists, "Connect to Server button should exist on welcome screen")
            connectToServerButton.click()
        } else {
            // Not on welcome screen - click the plus button in the sidebar
            let addConnectionButton = app.buttons["addConnectionButton"]
            XCTAssertTrue(addConnectionButton.waitForExistence(timeout: 2), "Add connection button should exist in sidebar")
            addConnectionButton.click()
        }

        // Verify connection form is shown by checking for the Host label
        let hostLabel = app.staticTexts["Host"]
        XCTAssertTrue(hostLabel.waitForExistence(timeout: 2), "Connection form should be displayed with Host field")
    }
}
