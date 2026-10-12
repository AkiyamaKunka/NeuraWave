import XCTest
@testable import NeuraWave

final class AutoTestOptionsTests: XCTestCase {
    func testAbsentWithoutTheFlag() {
        XCTAssertNil(AutoTestOptions(arguments: ["NeuraWave", "--autotest-seconds", "5"]))
    }

    func testDefaults() throws {
        let options = try XCTUnwrap(AutoTestOptions(arguments: ["NeuraWave", "--autotest"]))
        XCTAssertEqual(options.totalSeconds, 1800)
        XCTAssertEqual(options.cycleSeconds, 30)
        XCTAssertNil(options.timerMinutes)
        XCTAssertEqual(options.volume, 0.08)
        XCTAssertFalse(options.publishesNowPlaying)
        XCTAssertFalse(options.windowCheck)
    }

    func testBothArgumentFormsAndClamping() throws {
        let options = try XCTUnwrap(AutoTestOptions(arguments: [
            "NeuraWave", "--autotest",
            "--autotest-seconds=45", "--autotest-cycle", "1",
            "--autotest-timer-minutes", "0", "--autotest-volume=0",
            "--autotest-pause-at", "5", "--autotest-resume-at=12",
            "--autotest-device-change-at", "4", "--autotest-now-playing"
        ]))
        XCTAssertEqual(options.totalSeconds, 45)
        XCTAssertEqual(options.cycleSeconds, 2, "cycles shorter than 2 s are clamped")
        XCTAssertNil(options.timerMinutes, "0 means no timer")
        XCTAssertEqual(options.volume, 0)
        XCTAssertEqual(options.pauseAtSeconds, 5)
        XCTAssertEqual(options.resumeAtSeconds, 12)
        XCTAssertEqual(options.deviceChangeAtSeconds, 4)
        XCTAssertTrue(options.publishesNowPlaying)
    }

    func testMalformedNumbersFallBack() throws {
        let options = try XCTUnwrap(AutoTestOptions(arguments: ["NeuraWave", "--autotest", "--autotest-seconds", "abc"]))
        XCTAssertEqual(options.totalSeconds, 1800)
    }
}
