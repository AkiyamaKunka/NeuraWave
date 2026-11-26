import XCTest

/// A slow, scripted tour of the app: the ios-demo-video workflow records the
/// simulator while this runs, for App Review's "screen recording" request.
/// It also doubles as a smoke test that the main screen's controls work.
final class DemoWalkthroughTests: XCTestCase {
    private func pause(_ seconds: UInt32 = 2) { sleep(seconds) }

    func testWalkthrough() {
        let app = XCUIApplication()
        app.launch()
        pause(3)

        // Pick a preset, set a timer, start, pause, resume.
        app.staticTexts["Deep Focus"].tap()
        pause()
        app.buttons["No timer"].tap()
        pause(1)
        app.buttons["30 minutes"].tap()
        pause()
        app.buttons["Start"].tap()
        pause(5)
        app.buttons["Pause"].tap()
        pause()
        app.buttons["Resume"].tap()
        pause(3)

        // Sound settings: tone style, noise, then back.
        app.buttons["Sound settings"].tap()
        pause(3)
        if app.switches.firstMatch.exists {
            app.switches.firstMatch.tap()
            pause(2)
            app.switches.firstMatch.tap()
            pause(1)
        }
        app.buttons["Done"].tap()
        pause(2)
        app.buttons["Stop"].tap()
        pause(3)

        // A guided program.
        app.buttons["Programs"].tap()
        pause(2)
        app.staticTexts["Study Flow"].tap()
        pause(2)
        app.buttons["Start"].tap()
        pause(6)
        XCTAssertTrue(app.buttons["Stop"].exists)
        app.buttons["Stop"].tap()
        pause(3)
    }
}
