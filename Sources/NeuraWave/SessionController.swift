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

    let engine = AudioEngine()
    private let nowPlaying = NowPlayingController.shared
    private var sessionTitle = "NeuraWave"
    private var timer: Timer?
    private var endDate: Date?
    private var lastStartConfig: (preset: BrainwavePreset, style: ToneStyle, volume: Double, withNoise: Bool, minutes: Int?)?
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

    private struct AutoTestConfig {
        let preset: BrainwavePreset
        let style: ToneStyle
        let noise: Bool
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
        lastStartConfig = (preset, style, volume, withNoise, minutes)
        guard engine.start(preset: preset, style: style, volume: Float(volume), withNoise: withNoise) else {
            lastError = "Could not start audio. Check that an output device is connected and System Settings allows audio output."
            return
        }
        isPlaying = engine.isPlaying
        guard isPlaying else { return }
        isPaused = false
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
            start(preset: BrainwavePreset.byId("focus"), style: .binaural, volume: 0.55, withNoise: false, minutes: nil)
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
            lastError = "Could not start audio. Check that an output device is connected and System Settings allows audio output."
            return
        }
        isPlaying = true
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
        nowPlaying.clear()
    }

    func clearError() {
        lastError = nil
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
        let remaining = Int(ceil(end.timeIntervalSinceNow))
        if remaining <= 0 {
            stop()
        } else {
            remainingSeconds = remaining
            pushNowPlaying()
        }
    }

    private func tickProgram(_ program: FocusProgram) {
        let elapsed = Date().timeIntervalSince(programStartedAt)
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
            }
            if autotestRunning {
                logAutoTest("PROGRAM_STEP \(index + 1)/\(program.steps.count) \(preset.name) -> \(autotestSnapshot())")
            }
        }
        remainingSeconds = Int(ceil(program.totalSeconds - elapsed))
        pushNowPlaying()
    }

    // MARK: - Playback control (AirPods / Now Playing / menu bar)

    func pausePlayback() {
        guard isPlaying, !isPaused else { return }
        isPaused = true
        engine.pause()
        pushNowPlaying()
    }

    func resumePlayback() {
        guard isPlaying, isPaused else { return }
        isPaused = false
        engine.resume()
        pushNowPlaying()
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
        guard isPlaying, let cfg = lastStartConfig else { return }
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
            elapsed = min(Date().timeIntervalSince(programStartedAt), program.totalSeconds)
        } else if let end = endDate, let minutes = lastStartConfig?.minutes {
            duration = Double(minutes * 60)
            elapsed = max(0, duration! - Double(remainingSeconds ?? 0))
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
        programSeconds: Int
    ) {
        guard !autotestRunning else { return }
        setvbuf(stdout, nil, _IOLBF, 0)
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

        if elapsed >= Double(autotestTotal) {
            autotestTimer?.invalidate()
            autotestTimer = nil
            stop()
            logAutoTest("AUTOTEST_COMPLETE total=\(Int(elapsed))s -> \(autotestSnapshot())")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
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
        return "frames=\(diagnostics.frames) nan=\(diagnostics.nan) clips=\(diagnostics.clips) switches=\(diagnostics.switches) playing=\(isPlaying)"
    }

    private func logAutoTest(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        print("[autotest \(formatter.string(from: Date()))] \(message)")
    }
}
