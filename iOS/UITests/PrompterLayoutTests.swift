import XCTest

/// Opens the script picker, starts the prompter on the first script and walks both orientations.
/// Screenshots are attached to the test result, so the layout can be checked by eye.
final class PrompterLayoutTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPickerAndRecordingLayout() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))

        let navigationBar = app.navigationBars["Scripts"]
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 10), "The script picker should be the home screen")
        capture("picker")

        app.cells.firstMatch.tap()
        let record = app.buttons["camera.record"]
        XCTAssertTrue(record.waitForExistence(timeout: 10), "Choosing a script should open the recording screen")
        capture("portrait")

        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 1.5)
        capture("landscape-left")

        XCUIDevice.shared.orientation = .landscapeRight
        Thread.sleep(forTimeInterval: 1.5)
        capture("landscape-right")

        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 1.5)
        app.buttons["camera.exit"].tap()
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 5))
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
