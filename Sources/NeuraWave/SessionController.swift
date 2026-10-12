import Combine
import Foundation
import SwiftUI

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
    /// What the session is called right now (preset, or program · step).
    var displayTitle: String { sessionTitle }
    @Published private(set) var currentPreset: BrainwavePreset = BrainwavePreset.byId("focus")

    let engine = AudioEngine()
    private let nowPlaying = NowPlayingController.shared
    @Published private(set) var sessionTitle = "NeuraWave"
    private var timer: Timer?
    private var endDate: Date?
    private var lastStartConfig: (preset: BrainwavePreset, style: ToneStyle, volume: Double, withNoise: Bool, minutes: Int?)?
    /// Pause bookkeeping: pausing freezes the countdown (timer and program),
    /// resuming resumes it — a paused session never expires underneath you.
    private var pausedRemaining: TimeInterval?
    private var programPausedAt: Date?
    private var programPauseTotal: TimeInterval = 0
    /// Whole-second throttle for Now Playing metadata pushes.
    private var lastPushedSecond = -1
    private var program: FocusProgram?
    private var programStartedAt = Date()
    /// Set while the hidden self-test drives this session (see AutoTest.swift).
    weak var selfTest: AutoTestRunner?
    private var isSelfTesting: Bool { selfTest != nil }

    private static let audioFailureMessage = "Could not start audio. Check that an output device is connected and System Settings allows audio output."

    init() {
        // The output device went away (or changed) and couldn't be restarted:
        // stop rather than claim to be playing silence.
        engine.onOutputFailure = { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isPlaying else { return }
                self.stop()
                self.lastError = Self.audioFailureMessage
            }
        }
    }


    func start(
        preset: BrainwavePreset,
        style: ToneStyle,
        volume: Double,
        withNoise: Bool,
        minutes: Int?
    ) {
        stop()
        lastStartConfig = (preset, style, volume, withNoise, minutes)
        guard engine.start(preset: preset, style: style, volume: Float(volume), withNoise: withNoise) else {
            lastError = Self.audioFailureMessage
            return
        }
        isPlaying = engine.isPlaying
        guard isPlaying else { return }
        isPaused = false
        lastError = nil
        resetPauseBookkeeping()
        isRunningProgram = false
        currentPreset = preset
        rememberPreset(preset)
        sessionTitle = preset.name

        if let minutes {
            endDate = Date().addingTimeInterval(Double(minutes) * 60)
            remainingSeconds = minutes * 60
            scheduleCountdown()
        } else {
            endDate = nil
            remainingSeconds = nil
            timer?.invalidate()
            timer = nil
        }
        pushNowPlaying()
    }

    /// Start from the menu bar / AirPods while stopped: exactly what the
    /// window's Start button would play right now (program or preset, style,
    /// volume, noise, timer), all of which the window saves as you change
    /// them. Replaying an in-memory "last config" instead mixed stale and
    /// fresh settings (e.g. an old style or timer).
    func startLast() {
        startFromSavedSettings()
    }

    private func startFromSavedSettings() {
        let defaults = UserDefaults.standard
        let style = ToneStyle(rawValue: defaults.string(forKey: "style") ?? "") ?? .binaural
        let volume = VolumeLevel.sanitized(defaults.object(forKey: "volume") as? Double)
        let noise = defaults.bool(forKey: "noise")
        if let program = FocusProgram.all.first(where: { $0.id == defaults.string(forKey: "program") }) {
            startProgram(program, style: style, volume: volume, withNoise: noise)
            return
        }
        let preset = BrainwavePreset.all.first { $0.id == defaults.string(forKey: "preset") } ?? BrainwavePreset.byId("focus")
        let minutes = defaults.integer(forKey: "minutes")
        start(preset: preset, style: style, volume: volume, withNoise: noise, minutes: minutes > 0 ? minutes : nil)
    }

    /// The playing single preset becomes the saved choice, whoever picked it
    /// (window, menu bar, AirPods skip), so a reopened window and the next
    /// Start agree with what you last heard.
    private func rememberPreset(_ preset: BrainwavePreset) {
        guard !isSelfTesting, BrainwavePreset.all.contains(where: { $0.id == preset.id }) else { return }
        UserDefaults.standard.set(preset.id, forKey: "preset")
    }

    /// Menu bar "Presets" submenu: switch the playing preset in place, or
    /// start it fresh with the window's saved style, volume and timer.
    func playPreset(_ preset: BrainwavePreset) {
        if isPlaying, program == nil, let cfg = lastStartConfig {
            if isPaused {
                resumePlayback()
            }
            switchPreset(preset: preset, style: cfg.style, volume: cfg.volume, withNoise: cfg.withNoise)
            return
        }
        let defaults = UserDefaults.standard
        let style = ToneStyle(rawValue: defaults.string(forKey: "style") ?? "") ?? .binaural
        let volume = VolumeLevel.sanitized(defaults.object(forKey: "volume") as? Double)
        let minutes = defaults.integer(forKey: "minutes")
        start(preset: preset, style: style, volume: volume, withNoise: defaults.bool(forKey: "noise"), minutes: minutes > 0 ? minutes : nil)
    }

    /// Runs a timed program: presets auto-advance through the click-free
    /// crossfade, and the session stops itself when the schedule ends.
    func startProgram(_ program: FocusProgram, style: ToneStyle, volume: Double, withNoise: Bool) {
        stop()
        let first = program.steps[0].preset
        lastStartConfig = (first, style, volume, withNoise, nil)
        guard engine.start(preset: first, style: style, volume: Float(volume), withNoise: withNoise) else {
            lastError = Self.audioFailureMessage
            return
        }
        isPlaying = true
        lastError = nil
        resetPauseBookkeeping()
        isRunningProgram = true
        if publishesNowPlaying {
            nowPlaying.setSkipEnabled(false)
        }
        currentPreset = first
        self.program = program
        programStartedAt = Date()
        programStep = (0, program.steps.count)
        programTitle = programTitleString(program, index: 0)
        sessionTitle = program.name
        isPaused = false
        remainingSeconds = Int(program.totalSeconds)
        scheduleCountdown()
        pushNowPlaying()
    }

    private func programTitleString(_ program: FocusProgram, index: Int) -> String {
        let step = program.steps[index]
        return "\(program.name) · \(step.preset.name) (\(Int(step.seconds / 60)) min)"
    }

    func switchPreset(
        preset: BrainwavePreset,
        style: ToneStyle,
        volume: Double,
        withNoise: Bool
    ) {
        guard isPlaying else { return }
        engine.switchTo(preset: preset, style: style, volume: Float(volume), withNoise: withNoise)
        lastStartConfig = (preset, style, volume, withNoise, lastStartConfig?.minutes)
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
        guard isPlaying, program == nil, let cfg = lastStartConfig else { return }
        lastStartConfig = (cfg.preset, cfg.style, cfg.volume, cfg.withNoise, minutes)
        if let minutes {
            if isPaused {
                pausedRemaining = Double(minutes) * 60
                endDate = nil
            } else {
                endDate = Date().addingTimeInterval(Double(minutes) * 60)
            }
            remainingSeconds = minutes * 60
            scheduleCountdown()
        } else {
            endDate = nil
            pausedRemaining = nil
            remainingSeconds = nil
            timer?.invalidate()
            timer = nil
        }
        lastPushedSecond = -1
        pushNowPlaying()
    }

    /// Immediate volume/noise change while playing (no crossfade needed).
    func updateLive(volume: Double, noiseEnabled: Bool) {
        engine.update(volume: Float(volume), noiseEnabled: noiseEnabled)
        if lastStartConfig != nil {
            lastStartConfig = (lastStartConfig!.preset, lastStartConfig!.style, volume, noiseEnabled, lastStartConfig!.minutes)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        endDate = nil
        engine.stop()
        isPlaying = false
        remainingSeconds = nil
        program = nil
        programStep = nil
        programTitle = nil
        isPaused = false
        isRunningProgram = false
        resetPauseBookkeeping()
        if publishesNowPlaying {
            nowPlaying.setSkipEnabled(true)
            nowPlaying.clear()
        }
    }

    func clearError() {
        lastError = nil
    }

    private func resetPauseBookkeeping() {
        pausedRemaining = nil
        programPausedAt = nil
        programPauseTotal = 0
        lastPushedSecond = -1
    }

    private func scheduleCountdown() {
        timer?.invalidate()
        let newTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        // .common mode keeps the countdown running while menus are open.
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func tick() {
        if let program {
            tickProgram(program)
            return
        }
        guard let end = endDate else { return }
        // Deadline-based: immune to timer drift and run-loop stalls.
        // (endDate is nil while paused, so a paused countdown stays frozen.)
        let remaining = Int(ceil(end.timeIntervalSinceNow))
        if remaining <= 0 {
            stop()
        } else {
            remainingSeconds = remaining
            if remaining != lastPushedSecond {
                lastPushedSecond = remaining
                pushNowPlaying()
            }
        }
    }

    private func tickProgram(_ program: FocusProgram) {
        guard !isPaused else { return } // paused programs freeze in place
        let elapsed = programElapsed()
        if elapsed >= program.totalSeconds {
            stop() // fade out; stop() also clears the program state
            return
        }
        let index = program.stepIndex(at: elapsed)
        if index != programStep?.index {
            programStep = (index, program.steps.count)
            programTitle = programTitleString(program, index: index)
            sessionTitle = programTitle!
            let preset = program.steps[index].preset
            if let cfg = lastStartConfig {
                engine.switchTo(preset: preset, style: cfg.style, volume: Float(cfg.volume), withNoise: cfg.withNoise)
                lastStartConfig = (preset, cfg.style, cfg.volume, cfg.withNoise, nil)
                currentPreset = preset
            }
            selfTest?.programStepped(to: index, of: program.steps.count, preset: preset)
        }
        remainingSeconds = Int(ceil(program.totalSeconds - elapsed))
        let second = Int(elapsed)
        if second != lastPushedSecond {
            lastPushedSecond = second
            pushNowPlaying()
        }
    }

    /// Program time actually played: wall time since start minus every pause,
    /// including the one in progress.
    private func programElapsed(now: Date = Date()) -> TimeInterval {
        var paused = programPauseTotal
        if let pausedAt = programPausedAt {
            paused += now.timeIntervalSince(pausedAt)
        }
        return max(0, now.timeIntervalSince(programStartedAt) - paused)
    }

    // MARK: - Playback control (AirPods / Now Playing / menu bar)

    func pausePlayback() {
        guard isPlaying, !isPaused else { return }
        isPaused = true
        if let end = endDate {
            // Freeze the countdown: the deadline is parked while paused and
            // reinstated with the same remaining time on resume.
            pausedRemaining = max(0, end.timeIntervalSinceNow)
            endDate = nil
        }
        if program != nil {
            programPausedAt = Date()
        }
        engine.pause()
        pushNowPlaying()
    }

    func resumePlayback() {
        guard isPlaying, isPaused else { return }
        isPaused = false
        if let frozen = pausedRemaining {
            endDate = Date().addingTimeInterval(frozen)
            pausedRemaining = nil
        }
        if let pausedAt = programPausedAt {
            programPauseTotal += Date().timeIntervalSince(pausedAt)
            programPausedAt = nil
        }
        guard engine.restartAfterPause() else {
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
        if isPlaying {
            if isPaused {
                resumePlayback()
            } else {
                pausePlayback()
            }
        } else {
            startLast()
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
        guard isPlaying, program == nil, let cfg = lastStartConfig else { return }
        let all = BrainwavePreset.all
        guard let currentIndex = all.firstIndex(where: { $0.id == cfg.preset.id }) else { return }
        let nextIndex = (currentIndex + delta + all.count) % all.count
        switchPreset(preset: all[nextIndex], style: cfg.style, volume: cfg.volume, withNoise: cfg.withNoise)
    }

    /// Self-tests stay out of Control Center / Now Playing (they would take
    /// it over from whatever you're listening to) unless asked to cover it
    /// with --autotest-now-playing.
    private var publishesNowPlaying: Bool {
        selfTest?.options.publishesNowPlaying ?? true
    }

    private func pushNowPlaying() {
        guard isPlaying else { return }
        var elapsed: TimeInterval = 0
        var duration: TimeInterval?
        if let program {
            duration = program.totalSeconds
            elapsed = min(programElapsed(), program.totalSeconds)
        } else if let minutes = lastStartConfig?.minutes {
            let total = Double(minutes * 60)
            duration = total
            elapsed = max(0, total - Double(remainingSeconds ?? 0))
        }
        if publishesNowPlaying {
            nowPlaying.update(title: sessionTitle, elapsed: elapsed, duration: duration, playing: true, paused: isPaused)
        }
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
