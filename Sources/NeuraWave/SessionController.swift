import Combine
import Foundation
import SwiftUI

/// The one playback session behind the window, the menu bar, AirPods and
/// Control Center: what is playing, timers and focus programs, pause/resume,
/// and the Now Playing metadata. Sound itself is produced by `AudioEngine`.
@MainActor
final class SessionController: ObservableObject {
    /// One app-wide instance shared by the window and the menu bar item.
    static let shared = SessionController()

    @Published private(set) var isPlaying = false
    @Published private(set) var isPaused = false
    @Published private(set) var remainingSeconds: Int?
    @Published private(set) var lastError: String?
    @Published private(set) var programTitle: String?
    @Published private(set) var programStep: (index: Int, count: Int)?
    @Published private(set) var isRunningProgram = false
    @Published private(set) var currentPreset: BrainwavePreset = BrainwavePreset.byId(SettingsStore.defaultPresetID)
    /// What the session is called right now (preset, or "Program · Step").
    @Published private(set) var sessionTitle = "NeuraWave"

    let audio: AudioOutput
    /// The real engine when running for real (self-tests and diagnostics).
    var engine: AudioEngine? { audio as? AudioEngine }
    var settings: SettingsStore
    /// Set while the hidden self-test drives this session (see AutoTest.swift).
    weak var selfTest: AutoTestRunner?

    /// The sound being played (program steps change `preset` as they go).
    private struct PlaybackConfig {
        var preset: BrainwavePreset
        var style: ToneStyle
        var volume: Double
        var noise: Bool
    }

    private let nowPlaying: NowPlayingPublishing
    private let now: () -> Date
    private var playback: PlaybackConfig?
    private var clock: SessionClock?
    private var program: FocusProgram?
    private var ticker: Timer?

    private static let audioFailureMessage = "Could not start audio. Check that an output device is connected and System Settings allows audio output."

    init(
        audio: AudioOutput? = nil,
        nowPlaying: NowPlayingPublishing? = nil,
        settings: SettingsStore = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.audio = audio ?? AudioEngine()
        self.nowPlaying = nowPlaying ?? NowPlayingController.shared
        self.settings = settings
        self.now = now
        // The output device went away (or changed) and couldn't be restarted:
        // stop rather than claim to be playing silence.
        self.audio.onOutputFailure = { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isPlaying else { return }
                self.stop()
                self.lastError = Self.audioFailureMessage
            }
        }
    }

    private var isSelfTesting: Bool { selfTest != nil }

    // MARK: - Starting

    /// Plays one preset, optionally with a sleep timer.
    func start(preset: BrainwavePreset, style: ToneStyle, volume: Double, withNoise: Bool, minutes: Int?) {
        let config = PlaybackConfig(preset: preset, style: style, volume: volume, noise: withNoise)
        guard begin(config, duration: minutes.map { Double($0) * 60 }) else { return }
        currentPreset = preset
        sessionTitle = preset.name
        rememberPreset(preset)
        pushNowPlaying()
    }

    /// Runs a timed program: presets auto-advance through the click-free
    /// crossfade, and the session stops itself when the schedule ends.
    func startProgram(_ program: FocusProgram, style: ToneStyle, volume: Double, withNoise: Bool) {
        let first = program.steps[0].preset
        let config = PlaybackConfig(preset: first, style: style, volume: volume, noise: withNoise)
        guard begin(config, duration: program.totalSeconds) else { return }
        self.program = program
        isRunningProgram = true
        if publishesNowPlaying {
            nowPlaying.setSkipEnabled(false)
        }
        currentPreset = first
        programStep = (0, program.steps.count)
        programTitle = Self.title(of: program, step: 0)
        sessionTitle = program.name
        pushNowPlaying()
    }

    /// Shared start sequence: stop whatever plays, start the engine, set up
    /// the clock and countdown. False (with `lastError` set) on failure.
    private func begin(_ config: PlaybackConfig, duration: TimeInterval?) -> Bool {
        stop()
        playback = config
        guard audio.start(preset: config.preset, style: config.style, volume: Float(config.volume), withNoise: config.noise) else {
            lastError = Self.audioFailureMessage
            return false
        }
        isPlaying = true
        isPaused = false
        lastError = nil
        clock = SessionClock(startedAt: now(), duration: duration)
        remainingSeconds = duration.map { Int($0) }
        updateTicker()
        return true
    }

    /// Start from the menu bar / AirPods while stopped: exactly what the
    /// window's Start button would play right now (program or preset, style,
    /// volume, noise, timer), all of which the window saves as you change
    /// them. Replaying an in-memory "last config" instead mixed stale and
    /// fresh settings (e.g. an old style or timer).
    func startLast() {
        if let program = settings.program {
            startProgram(program, style: settings.style, volume: settings.volume, withNoise: settings.noise)
        } else {
            startSaved(preset: settings.preset)
        }
    }

    /// `preset` with the saved style, volume, noise and timer.
    private func startSaved(preset: BrainwavePreset) {
        start(preset: preset, style: settings.style, volume: settings.volume, withNoise: settings.noise, minutes: settings.minutes)
    }

    /// Menu bar "Presets" submenu: switch the playing preset in place, or
    /// start it fresh with the window's saved style, volume and timer.
    func playPreset(_ preset: BrainwavePreset) {
        if isPlaying, program == nil, let playback {
            if isPaused {
                resumePlayback()
            }
            switchPreset(preset: preset, style: playback.style, volume: playback.volume, withNoise: playback.noise)
            return
        }
        startSaved(preset: preset)
    }

    /// The playing single preset becomes the saved choice, whoever picked it
    /// (window, menu bar, AirPods skip), so a reopened window and the next
    /// Start agree with what you last heard.
    private func rememberPreset(_ preset: BrainwavePreset) {
        guard !isSelfTesting, BrainwavePreset.all.contains(where: { $0.id == preset.id }) else { return }
        settings.preset = preset
    }

    // MARK: - Live changes

    func switchPreset(preset: BrainwavePreset, style: ToneStyle, volume: Double, withNoise: Bool) {
        guard isPlaying else { return }
        audio.switchTo(preset: preset, style: style, volume: Float(volume), withNoise: withNoise)
        playback = PlaybackConfig(preset: preset, style: style, volume: volume, noise: withNoise)
        currentPreset = preset
        if program == nil {
            // During a program the title stays "Program · Step".
            sessionTitle = preset.name
            rememberPreset(preset)
        }
        pushNowPlaying()
    }

    /// Timer picked or changed while a single-preset session plays: apply it
    /// now (counted from this moment) instead of silently waiting for the
    /// next Start. Programs have their own schedule and ignore this.
    func updateTimer(minutes: Int?) {
        guard isPlaying, program == nil, var clock else { return }
        let now = self.now()
        clock.setRemaining(minutes.map { Double($0) * 60 }, at: now)
        self.clock = clock
        publishRemaining(clock.remaining(at: now))
        updateTicker()
        pushNowPlaying()
    }

    /// Immediate volume/noise change (no crossfade needed). Also fine while
    /// stopped: the engine keeps the level for the next start.
    func updateLive(volume: Double, noiseEnabled: Bool) {
        audio.update(volume: Float(volume), noiseEnabled: noiseEnabled)
        playback?.volume = volume
        playback?.noise = noiseEnabled
    }

    // MARK: - Stopping

    func stop() {
        ticker?.invalidate()
        ticker = nil
        audio.stop()
        isPlaying = false
        isPaused = false
        remainingSeconds = nil
        clock = nil
        program = nil
        programStep = nil
        programTitle = nil
        isRunningProgram = false
        if publishesNowPlaying {
            nowPlaying.setSkipEnabled(true)
            nowPlaying.clear()
        }
    }

    func clearError() {
        lastError = nil
    }

    // MARK: - Countdown

    /// Ticks only while there is something to count down (a sleep timer or a
    /// program). Deadline-based via the clock, so timer drift and run-loop
    /// stalls don't accumulate.
    private func updateTicker() {
        guard clock?.duration != nil else {
            ticker?.invalidate()
            ticker = nil
            return
        }
        guard ticker == nil else { return }
        let newTicker = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // .common mode keeps the countdown running while menus are open.
        RunLoop.main.add(newTicker, forMode: .common)
        ticker = newTicker
    }

    /// Advance timers/programs (driven by the ticker; tests call it directly).
    func tick() {
        guard isPlaying, !isPaused, let clock else { return }
        let now = self.now()
        if clock.isFinished(at: now) {
            stop() // fade out; stop() also clears timer and program state
            return
        }
        if let program {
            advanceProgram(program, elapsed: clock.elapsed(at: now))
        }
        publishRemaining(clock.remaining(at: now))
    }

    /// The countdown ticks twice a second but its value changes once a second;
    /// only publish real changes so observers (the window) don't redraw for
    /// nothing.
    private func publishRemaining(_ remaining: TimeInterval?) {
        let seconds = remaining.map { Int(ceil($0)) }
        if seconds != remainingSeconds {
            remainingSeconds = seconds
        }
    }

    private func advanceProgram(_ program: FocusProgram, elapsed: TimeInterval) {
        let index = program.stepIndex(at: elapsed)
        guard index != programStep?.index else { return }
        let preset = program.steps[index].preset
        programStep = (index, program.steps.count)
        programTitle = Self.title(of: program, step: index)
        sessionTitle = programTitle ?? program.name
        if let playback {
            audio.switchTo(preset: preset, style: playback.style, volume: Float(playback.volume), withNoise: playback.noise)
            self.playback?.preset = preset
            currentPreset = preset
        }
        pushNowPlaying()
        selfTest?.programStepped(to: index, of: program.steps.count, preset: preset)
    }

    private static func title(of program: FocusProgram, step index: Int) -> String {
        let step = program.steps[index]
        return "\(program.name) · \(step.preset.name) (\(Int(step.seconds / 60)) min)"
    }

    // MARK: - Playback control (AirPods / Now Playing / menu bar)

    func pausePlayback() {
        guard isPlaying, !isPaused else { return }
        isPaused = true
        clock?.pause(at: now())
        audio.pause()
        pushNowPlaying()
    }

    func resumePlayback() {
        guard isPlaying, isPaused else { return }
        isPaused = false
        clock?.resume(at: now())
        guard audio.restartAfterPause() else {
            stop()
            lastError = Self.audioFailureMessage
            return
        }
        pushNowPlaying()
        // Some macOS versions re-sync Now Playing state shortly after a rate
        // change; re-push once the fade-in is underway.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.pushNowPlaying()
        }
    }

    func resumeOrStart() {
        if isPlaying {
            resumePlayback()
        } else {
            startLast()
        }
    }

    func togglePlayPause() {
        if !isPlaying {
            startLast()
        } else if isPaused {
            resumePlayback()
        } else {
            pausePlayback()
        }
    }

    /// AirPods double-press: step through presets while a session is active.
    func nextPreset() {
        stepPreset(by: 1)
    }

    func previousPreset() {
        stepPreset(by: -1)
    }

    private func stepPreset(by delta: Int) {
        // A running program owns the preset sequence; skipping would fight
        // its schedule (and be undone at the next step).
        guard isPlaying, program == nil, let playback else { return }
        let all = BrainwavePreset.all
        guard let currentIndex = all.firstIndex(where: { $0.id == playback.preset.id }) else { return }
        let nextIndex = (currentIndex + delta + all.count) % all.count
        switchPreset(preset: all[nextIndex], style: playback.style, volume: playback.volume, withNoise: playback.noise)
    }

    // MARK: - Now Playing

    /// Self-tests stay out of Control Center / Now Playing (they would take
    /// it over from whatever you're listening to) unless asked to cover it
    /// with --autotest-now-playing.
    private var publishesNowPlaying: Bool {
        selfTest?.options.publishesNowPlaying ?? true
    }

    /// Publishes title, elapsed time, duration and rate. Called on state
    /// changes only: with a playback rate set, macOS advances the elapsed
    /// time itself, so per-second pushes would just be extra IPC.
    private func pushNowPlaying() {
        guard isPlaying, publishesNowPlaying, let clock else { return }
        let elapsed = clock.elapsed(at: now())
        nowPlaying.update(
            title: sessionTitle,
            elapsed: clock.duration.map { min(elapsed, $0) } ?? elapsed,
            duration: clock.duration,
            playing: true,
            paused: isPaused
        )
    }

    // MARK: - Self-test

    /// Remote commands (AirPods, Control Center, or macOS handing Now Playing
    /// to another app) arrive asynchronously from outside. During a self-test
    /// they would make results depend on whatever else the Mac is doing, so
    /// they are logged and ignored.
    func shouldHandleRemoteCommand(_ name: String) -> Bool {
        guard let selfTest else { return true }
        selfTest.remoteCommandIgnored(name)
        return false
    }
}
