import XCTest
@testable import NeuraWave

final class SessionClockTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    func testOpenEndedSessionNeverFinishes() {
        let clock = SessionClock(startedAt: t0, duration: nil)
        XCTAssertEqual(clock.elapsed(at: at(90)), 90)
        XCTAssertNil(clock.remaining(at: at(90)))
        XCTAssertFalse(clock.isFinished(at: at(1_000_000)))
    }

    func testTimerCountsDownAndFinishes() {
        let clock = SessionClock(startedAt: t0, duration: 60)
        XCTAssertEqual(clock.remaining(at: at(15)), 45)
        XCTAssertFalse(clock.isFinished(at: at(59.9)))
        XCTAssertTrue(clock.isFinished(at: at(60)))
        XCTAssertEqual(clock.remaining(at: at(500)), 0, "never negative")
    }

    /// The bug class this type exists for: paused time must not count.
    func testPausedTimeDoesNotCount() {
        var clock = SessionClock(startedAt: t0, duration: 60)
        clock.pause(at: at(10))
        XCTAssertTrue(clock.isPaused)
        XCTAssertEqual(clock.elapsed(at: at(40)), 10, "frozen while paused")
        XCTAssertFalse(clock.isFinished(at: at(100)), "a paused session can't expire")
        clock.resume(at: at(40))
        XCTAssertFalse(clock.isPaused)
        XCTAssertEqual(clock.elapsed(at: at(45)), 15)
        XCTAssertEqual(clock.remaining(at: at(45)), 45)
        XCTAssertTrue(clock.isFinished(at: at(90)), "ends 30 s late: the length of the pause")
    }

    func testRepeatedPausesAccumulateAndDoublePauseIsHarmless() {
        var clock = SessionClock(startedAt: t0, duration: nil)
        clock.pause(at: at(5))
        clock.pause(at: at(8)) // ignored: already paused
        clock.resume(at: at(10))
        clock.resume(at: at(12)) // ignored: not paused
        clock.pause(at: at(20))
        clock.resume(at: at(30))
        XCTAssertEqual(clock.elapsed(at: at(40)), 25) // 40 − 5 − 10
    }

    func testChangingTheTimerMidSession() {
        var clock = SessionClock(startedAt: t0, duration: nil)
        clock.setRemaining(30 * 60, at: at(600)) // picked "30 min" ten minutes in
        XCTAssertEqual(clock.remaining(at: at(600)), 30 * 60)
        XCTAssertEqual(clock.duration, 40 * 60, "progress keeps the ten minutes played")
        clock.setRemaining(nil, at: at(700)) // "No timer"
        XCTAssertNil(clock.remaining(at: at(700)))
        XCTAssertFalse(clock.isFinished(at: at(1_000_000)))
    }

    func testChangingTheTimerWhilePaused() {
        var clock = SessionClock(startedAt: t0, duration: 60)
        clock.pause(at: at(20))
        clock.setRemaining(15 * 60, at: at(50))
        XCTAssertEqual(clock.remaining(at: at(500)), 15 * 60, "still frozen")
        clock.resume(at: at(500))
        XCTAssertEqual(clock.remaining(at: at(560)), 15 * 60 - 60)
    }
}
