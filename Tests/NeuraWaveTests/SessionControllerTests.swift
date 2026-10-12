import XCTest
@testable import NeuraWave

@MainActor
final class SessionControllerTests: XCTestCase {
    private var audio: FakeAudio!
    private var nowPlaying: FakeNowPlaying!
    private var settings: SettingsStore!
    private var suiteName = ""
    private var clock = Date(timeIntervalSinceReferenceDate: 0)
    private var session: SessionController!

    override func setUp() async throws {
        audio = FakeAudio()
        nowPlaying = FakeNowPlaying()
        suiteName = "NeuraWaveTests.Session"
        settings = SettingsStore(defaults: UserDefaults(suiteName: suiteName)!)
        // Fixed name (no plist per run); clear leftovers from a killed run.
        settings.defaults.removePersistentDomain(forName: suiteName)
        clock = Date(timeIntervalSinceReferenceDate: 0)
        session = SessionController(audio: audio, nowPlaying: nowPlaying, settings: settings) { [unowned self] in self.clock }
    }

    override func tearDown() async throws {
        session.stop()
        settings.defaults.removePersistentDomain(forName: suiteName)
    }

    private func advance(_ seconds: TimeInterval) {
        clock = clock.addingTimeInterval(seconds)
        session.tick()
    }

    private func preset(_ id: String) -> BrainwavePreset { BrainwavePreset.byId(id) }
    private func program(_ id: String) -> FocusProgram { FocusProgram.all.first { $0.id == id }! }

    // MARK: Timer

    func testTimerSessionCountsDownAndStopsItself() {
        session.start(preset: preset("relax"), style: .binaural, volume: 0.4, withNoise: false, minutes: 30)
        XCTAssertTrue(session.isPlaying)
        XCTAssertEqual(session.remainingSeconds, 1800)
        XCTAssertEqual(nowPlaying.title, "Relax")
        XCTAssertEqual(nowPlaying.duration, 1800)

        advance(600)
        XCTAssertEqual(session.remainingSeconds, 1200)
        advance(1200)
        XCTAssertFalse(session.isPlaying)
        XCTAssertNil(session.remainingSeconds)
        XCTAssertEqual(audio.log.last, "stop")
        XCTAssertNil(nowPlaying.title, "Now Playing cleared")
    }

    func testPauseFreezesTheTimer() {
        session.start(preset: preset("relax"), style: .binaural, volume: 0.4, withNoise: false, minutes: 1)
        advance(10)
        session.pausePlayback()
        XCTAssertTrue(nowPlaying.paused)
        advance(600)
        XCTAssertTrue(session.isPlaying, "a paused session can't expire")
        XCTAssertEqual(session.remainingSeconds, 50)

        session.resumePlayback()
        XCTAssertFalse(session.isPaused)
        advance(49)
        XCTAssertTrue(session.isPlaying)
        advance(1)
        XCTAssertFalse(session.isPlaying)
    }

    func testTimersEaseOutOverTheirLastThirtySeconds() {
        session.start(preset: preset("deep-sleep"), style: .binaural, volume: 0.4, withNoise: false, minutes: 1)
        advance(29)
        XCTAssertFalse(audio.log.contains { $0.hasPrefix("update") }, "full level until the last 30 s")
        advance(16) // 15 s left: half way down
        XCTAssertEqual(audio.log.last, "update 0.2")
        session.updateLive(volume: 0.8, noiseEnabled: false)
        XCTAssertEqual(audio.log.last, "update 0.4", "a new level keeps easing out")
        session.updateTimer(minutes: 15)
        XCTAssertEqual(audio.log.last, "update 0.8", "extending the timer restores the level")
    }

    func testChangingTheTimerMidSessionAppliesNow() {
        session.start(preset: preset("relax"), style: .binaural, volume: 0.4, withNoise: false, minutes: nil)
        XCTAssertNil(session.remainingSeconds)
        advance(300)
        session.updateTimer(minutes: 15)
        XCTAssertEqual(session.remainingSeconds, 900)
        session.updateTimer(minutes: nil)
        XCTAssertNil(session.remainingSeconds)
        advance(100_000)
        XCTAssertTrue(session.isPlaying)
    }

    // MARK: Programs

    func testProgramAdvancesThroughItsStepsAndEnds() {
        session.startProgram(program("study"), style: .isochronic, volume: 0.4, withNoise: true)
        XCTAssertTrue(session.isRunningProgram)
        XCTAssertEqual(session.currentPreset.id, "relax")
        XCTAssertFalse(nowPlaying.skipEnabled, "AirPods skip is off during programs")

        advance(10 * 60)
        XCTAssertEqual(session.currentPreset.id, "focus")
        XCTAssertEqual(audio.log.last, "switch focus Isochronic", "keeps the session's style")
        XCTAssertEqual(session.programStep?.index, 1)
        XCTAssertTrue(session.programTitle?.contains("Deep Focus") ?? false)

        advance(30 * 60)
        XCTAssertFalse(session.isPlaying)
        XCTAssertFalse(session.isRunningProgram)
        XCTAssertTrue(nowPlaying.skipEnabled)
    }

    func testPausedProgramDoesNotAdvance() {
        session.startProgram(program("study"), style: .binaural, volume: 0.4, withNoise: false)
        advance(9 * 60)
        session.pausePlayback()
        advance(60 * 60)
        XCTAssertEqual(session.currentPreset.id, "relax")
        session.resumePlayback()
        advance(60)
        XCTAssertEqual(session.currentPreset.id, "focus")
    }

    func testSkippingIsIgnoredDuringAProgramButWrapsOtherwise() {
        session.startProgram(program("study"), style: .binaural, volume: 0.4, withNoise: false)
        session.nextPreset()
        XCTAssertEqual(session.currentPreset.id, "relax")
        session.stop()

        session.start(preset: BrainwavePreset.all.last!, style: .binaural, volume: 0.4, withNoise: false, minutes: nil)
        session.nextPreset()
        XCTAssertEqual(session.currentPreset.id, BrainwavePreset.all.first!.id)
        session.previousPreset()
        XCTAssertEqual(session.currentPreset.id, BrainwavePreset.all.last!.id)
    }

    // MARK: Starting from the menu bar / AirPods

    func testStartLastPlaysTheSavedChoices() {
        settings.preset = preset("meditation")
        settings.style = .isochronic
        settings.minutes = 15
        session.startLast()
        XCTAssertEqual(audio.lastPreset?.id, "meditation")
        XCTAssertEqual(audio.lastStyle, .isochronic)
        XCTAssertEqual(session.remainingSeconds, 900)

        session.stop()
        settings.program = program("rest")
        session.togglePlayPause()
        XCTAssertTrue(session.isRunningProgram)
    }

    func testPlayingPresetsIsRemembered() {
        session.start(preset: preset("relax"), style: .binaural, volume: 0.4, withNoise: false, minutes: nil)
        session.playPreset(preset("peak"))
        XCTAssertEqual(settings.preset.id, "peak")
        session.pausePlayback()
        session.playPreset(preset("meditation"))
        XCTAssertFalse(session.isPaused, "picking a preset while paused resumes")
        XCTAssertEqual(session.currentPreset.id, "meditation")
    }

    // MARK: Failures

    func testStartFailureReportsAnError() {
        audio.startSucceeds = false
        session.start(preset: preset("relax"), style: .binaural, volume: 0.4, withNoise: false, minutes: nil)
        XCTAssertFalse(session.isPlaying)
        XCTAssertNotNil(session.lastError)

        audio.startSucceeds = true
        session.start(preset: preset("relax"), style: .binaural, volume: 0.4, withNoise: false, minutes: nil)
        XCTAssertNil(session.lastError, "a successful start clears the error")
    }

    func testResumeFailureStopsWithAnError() {
        session.start(preset: preset("relax"), style: .binaural, volume: 0.4, withNoise: false, minutes: nil)
        session.pausePlayback()
        audio.restartSucceeds = false
        session.resumePlayback()
        XCTAssertFalse(session.isPlaying)
        XCTAssertNotNil(session.lastError)
    }

    func testLosingTheOutputDeviceStopsWithAnError() {
        session.start(preset: preset("relax"), style: .binaural, volume: 0.4, withNoise: false, minutes: nil)
        audio.onOutputFailure?()
        XCTAssertFalse(session.isPlaying)
        XCTAssertNotNil(session.lastError)
    }

    // MARK: Now Playing

    func testNowPlayingIsPushedOnChangesNotEveryTick() {
        session.startProgram(program("study"), style: .binaural, volume: 0.4, withNoise: false)
        let afterStart = nowPlaying.updates
        for _ in 0..<120 { advance(1) } // two quiet minutes
        XCTAssertEqual(nowPlaying.updates, afterStart, "macOS extrapolates elapsed time itself")
        advance(10 * 60) // next program step
        XCTAssertEqual(nowPlaying.updates, afterStart + 1)
        XCTAssertTrue(nowPlaying.title?.contains("Deep Focus") ?? false)
        session.pausePlayback()
        XCTAssertEqual(nowPlaying.updates, afterStart + 2)
    }
}
