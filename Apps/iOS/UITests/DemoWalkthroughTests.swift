import XCTest

/// A slow, scripted tour of the app: the ios-demo-video workflow records the
/// simulator while this runs, for App Review's "screen recording" request.
/// It also doubles as a smoke test that the main screen's controls work.
final class DemoWalkthroughTests: XCTestCase {
    private func pause(_ seconds: UInt32 = 2) { sleep(seconds) }

    /// Taps the first element with this label, waiting briefly for it.
    private func tap(_ query: XCUIElementQuery, _ label: String) {
        let element = query[label].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 5), "\(label) not found")
        element.tap()
    }

    func testWalkthrough() {
        let app = XCUIApplication()
        app.launch()
        pause(3)

        // Pick a preset, set a timer, start, pause, resume.
        tap(app.staticTexts, "Calm Focus")
        pause()
        tap(app.buttons, "No timer")
        pause(1)
        tap(app.buttons, "30 minutes")
        pause()
        tap(app.buttons, "Start")
        pause(5)
        tap(app.buttons, "Pause")
        pause()
        tap(app.buttons, "Resume")
        pause(3)

        // Sound settings: tone style, noise, then back.
        tap(app.buttons, "Sound settings")
        pause(3)
        if app.switches.firstMatch.exists {
            app.switches.firstMatch.tap()
            pause(2)
            app.switches.firstMatch.tap()
            pause(1)
        }
        tap(app.buttons, "Done")
        pause(2)
        tap(app.buttons, "Stop")
        pause(3)

        // A guided program.
        tap(app.buttons, "Programs")
        pause(2)
        tap(app.staticTexts, "Study Flow")
        pause(2)
        tap(app.buttons, "Start")
        pause(6)
        XCTAssertTrue(app.buttons["Stop"].firstMatch.exists)
        tap(app.buttons, "Stop")
        pause(3)
    }
}
