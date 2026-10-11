import Combine
import Darwin
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
    @Published private(set) var currentPreset: BrainwavePreset = BrainwavePreset.byId("focus")

    let engine = AudioEngine()
    private let nowPlaying = NowPlayingController.shared
    private var sessionTitle = "NeuraWave"
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
    private var lastProgram: FocusProgram?
    private var autotestProgram = false
    private var autotestRunning = false
    private var autotestTimer: Timer?
    private var autotestConfigIndex = 0
    private var autotestStartedAt = Date()
    private var autotestLastCycle = Date()
    private var autotestTotal = 0
    private var autotestCycle = 30
    private var autotestTimerMinutes: Int?
    private var autotestStopAt = 0
    private var autotestStopPerformed = false
    private var autotestTimerVerified = false
    private var autotestVolume: Double = 0.08
    private var autotestPauseAt = 0
    private var autotestResumeAt = 0
    private var autotestPausePerformed = false
    private var autotestResumePerformed = false
    private var autotestArguments: [String] = []

    private struct AutoTestConfig {
        let preset: BrainwavePreset
        let style: ToneStyle
        let noise: Bool
    }

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

    private static let autotestConfigs: [AutoTestConfig] = {
        var configs: [AutoTestConfig] = []
        for style in ToneStyle.allCases {
            for preset in BrainwavePreset.all {
                configs.append(AutoTestConfig(preset: preset, style: style, noise: false))
                configs.append(AutoTestConfig(preset: preset, style: style, noise: true))
            }
        }
        return configs
    }()

    func start(
        preset: BrainwavePreset,
        style: ToneStyle,
        volume: Double,
        withNoise: Bool,
        minutes: Int?
    ) {
        stop()
        // A single-preset session replaces any earlier program as "the last
        // thing played", so the menu bar / AirPods restart this, not that.
        lastProgram = nil
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

    /// Restarts the most recent configuration (used by the menu bar item).
    func startLast() {
        if let prog = lastProgram, let cfg = lastStartConfig {
            startProgram(prog, style: cfg.style, volume: cfg.volume, withNoise: cfg.withNoise)
            return
        }
        guard let last = lastStartConfig else {
            start(preset: BrainwavePreset.byId("focus"), style: .binaural, volume: 0.385, withNoise: false, minutes: nil)
            return
        }
        start(preset: last.preset, style: last.style, volume: last.volume, withNoise: last.withNoise, minutes: last.minutes)
    }

    /// Runs a timed program: presets auto-advance through the click-free
    /// crossfade, and the session stops itself when the schedule ends.
    func startProgram(_ program: FocusProgram, style: ToneStyle, volume: Double, withNoise: Bool) {
        stop()
        lastProgram = program
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
        sessionTitle = preset.name
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
        nowPlaying.clear()
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
        var acc: TimeInterval = 0
        var index = 0
        for (i, step) in program.steps.enumerated() {
            if elapsed < acc + step.seconds {
                index = i
                break
            }
            acc += step.seconds
        }
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
            if autotestRunning {
                logAutoTest("PROGRAM_STEP \(index + 1)/\(program.steps.count) \(preset.name) -> \(autotestSnapshot())")
            }
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
        nowPlaying.update(title: sessionTitle, elapsed: elapsed, duration: duration, playing: true, paused: isPaused)
    }

    // MARK: - Automated self-test (launched with --autotest)

    func runAutoTest(
        totalSeconds: Int,
        cycleSeconds: Int,
        timerMinutes: Int?,
        stopAtSeconds: Int,
        volume: Double,
        programSeconds: Int,
        arguments: [String] = []
    ) {
        guard !autotestRunning else { return }
        setvbuf(stdout, nil, _IOLBF, 0)
        autotestArguments = arguments
        autotestRunning = true
        autotestConfigIndex = 0
        autotestStartedAt = Date()
        autotestLastCycle = Date()
        autotestTotal = totalSeconds
        autotestCycle = max(2, cycleSeconds)
        autotestTimerMinutes = timerMinutes
        autotestStopAt = stopAtSeconds
        autotestStopPerformed = false
        autotestTimerVerified = false
        autotestVolume = volume
        autotestProgram = programSeconds > 0
        autotestPauseAt = intArgument(arguments, name: "--autotest-pause-at", fallback: 0)
        autotestResumeAt = intArgument(arguments, name: "--autotest-resume-at", fallback: 0)
        autotestPausePerformed = false
        autotestResumePerformed = false

        let first = Self.autotestConfigs[0]
        if autotestProgram {
            let third = max(3, programSeconds / 3)
            let prog = FocusProgram(
                id: "autotest",
                name: "Autotest Program",
                detail: "",
                steps: [
                    FocusProgram.ProgramStep(preset: BrainwavePreset.all.first { $0.id == "relax" }!, seconds: TimeInterval(third)),
                    FocusProgram.ProgramStep(preset: BrainwavePreset.all.first { $0.id == "focus" }!, seconds: TimeInterval(third)),
                    FocusProgram.ProgramStep(preset: BrainwavePreset.all.first { $0.id == "peak" }!, seconds: TimeInterval(programSeconds - 2 * third))
                ]
            )
            startProgram(prog, style: .binaural, volume: volume, withNoise: true)
            logAutoTest("START_PROGRAM -> \(autotestSnapshot())")
        } else if let minutes = timerMinutes {
            start(
                preset: first.preset,
                style: first.style,
                volume: volume,
                withNoise: first.noise,
                minutes: minutes
            )
            logAutoTest("START_WITH_TIMER \(minutes)m -> \(autotestSnapshot())")
        } else {
            autotestApplyConfig(volume: volume)
            logAutoTest("START -> \(autotestSnapshot())")
        }

        autotestTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.autotestTick()
            }
        }
    }

    private func autotestTick() {
        let elapsed = Date().timeIntervalSince(autotestStartedAt)

        if autotestTimerMinutes != nil, !autotestTimerVerified, !isPlaying, !autotestStopPerformed, !autotestProgram {
            autotestTimerVerified = true
            logAutoTest("TIMER_STOP_VERIFIED at \(Int(elapsed))s -> \(autotestSnapshot())")
            if elapsed < Double(autotestTotal) - 8 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    guard let self else { return }
                    self.autotestApplyConfig(volume: self.autotestVolume)
                    self.logAutoTest("RESTART_AFTER_TIMER -> \(self.autotestSnapshot())")
                }
            }
        }

        if autotestStopAt > 0, !autotestStopPerformed, !autotestProgram, Int(elapsed) >= autotestStopAt {
            autotestStopPerformed = true
            logAutoTest("MANUAL_STOP at \(autotestStopAt)s -> \(autotestSnapshot())")
            stop()
            if elapsed < Double(autotestTotal) - 8 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    guard let self else { return }
                    self.autotestConfigIndex += 1
                    self.autotestApplyConfig(volume: self.autotestVolume)
                    self.logAutoTest("RESTART_AFTER_STOP -> \(self.autotestSnapshot())")
                }
            }
        }

        // Preset cycling continues after stop/restart so the whole matrix is
        // exercised across the run (previously it stopped after a manual stop).
        if elapsed - autotestLastCycle.timeIntervalSince(autotestStartedAt) >= Double(autotestCycle),
           isPlaying, !autotestProgram {
            autotestLastCycle = Date()
            autotestConfigIndex += 1
            let config = Self.autotestConfigs[autotestConfigIndex % Self.autotestConfigs.count]
            if autotestConfigIndex % 3 == 2 {
                let newVolume = Float(autotestVolume * (0.7 + 0.15 * Double(autotestConfigIndex % 4)))
                engine.update(volume: newVolume, noiseEnabled: config.noise)
                logAutoTest("LIVE_UPDATE volume=\(newVolume) noise=\(config.noise)")
            } else {
                autotestApplyConfig(volume: autotestVolume)
            }
            logAutoTest("cycle diag -> \(autotestSnapshot())")
        }

        if autotestPauseAt > 0, !autotestPausePerformed, Int(elapsed) >= autotestPauseAt, isPlaying, !isPaused {
            autotestPausePerformed = true
            pausePlayback()
            logAutoTest("AUTOTEST_PAUSE at \(Int(elapsed))s -> \(autotestSnapshot())")
        }

        if autotestResumeAt > 0, !autotestResumePerformed, Int(elapsed) >= autotestResumeAt, isPlaying, isPaused {
            autotestResumePerformed = true
            resumePlayback()
            logAutoTest("AUTOTEST_RESUME at \(Int(elapsed))s -> \(autotestSnapshot())")
        }

        if elapsed >= Double(autotestTotal) {
            autotestTimer?.invalidate()
            autotestTimer = nil
            stop()
            logAutoTest("AUTOTEST_COMPLETE total=\(Int(elapsed))s -> \(autotestSnapshot())")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                // Every requested preset/style change must reach the render
                // thread (a lost update here once dropped ~30% of switches).
                if let self {
                    let requested = self.engine.switchRequests
                    let applied = self.engine.diagnostics.switches
                    self.logAutoTest("SWITCH_CHECK \(requested == applied ? "ok" : "MISMATCH") requested=\(requested) applied=\(applied)")
                }
                exit(0)
            }
        }
    }

    private func autotestApplyConfig(volume: Double) {
        let config = Self.autotestConfigs[autotestConfigIndex % Self.autotestConfigs.count]
        if engine.isPlaying {
            // Exercises the live crossfade-switch path.
            engine.switchTo(preset: config.preset, style: config.style, volume: Float(volume), withNoise: config.noise)
        } else {
            _ = engine.start(preset: config.preset, style: config.style, volume: Float(volume), withNoise: config.noise)
        }
        isPlaying = engine.isPlaying
        logAutoTest("switch -> \(config.preset.name)/\(config.style.rawValue)/noise=\(config.noise) volume=\(volume)")
    }

    private func autotestSnapshot() -> String {
        let diagnostics = engine.diagnostics
        return "frames=\(diagnostics.frames) nan=\(diagnostics.nan) clips=\(diagnostics.clips) switches=\(diagnostics.switches) gain=\(String(format: "%.2f", diagnostics.gain)) playing=\(isPlaying)"
    }

    private func intArgument(_ arguments: [String], name: String, fallback: Int) -> Int {
        guard let raw = argumentValue(arguments, name: name) else { return fallback }
        return Int(raw) ?? fallback
    }

    private func argumentValue(_ arguments: [String], name: String) -> String? {
        if let equalsForm = arguments.first(where: { $0.hasPrefix(name + "=") }) {
            return String(equalsForm.dropFirst(name.count + 1))
        }
        if let index = arguments.firstIndex(of: name), index + 1 < arguments.count {
            return arguments[index + 1]
        }
        return nil
    }

    private func logAutoTest(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        print("[autotest \(formatter.string(from: Date()))] \(message)")
    }
}
