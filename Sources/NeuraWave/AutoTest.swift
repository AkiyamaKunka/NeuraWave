import AppKit
import Darwin
import Foundation
import NeuraWaveCore

/// Command-line options for the hidden self-test mode (`--autotest`).
/// Every flag takes `--name value` or `--name=value`.
struct AutoTestOptions {
    var totalSeconds = 1800
    var cycleSeconds = 30
    var timerMinutes: Int?
    var stopAtSeconds = 0
    var volume = 0.08
    var programSeconds = 0
    var pauseAtSeconds = 0
    var resumeAtSeconds = 0
    var deviceChangeAtSeconds = 0
    /// Publish Now Playing during the run (off by default so a self-test
    /// never takes Control Center over from whatever you're listening to).
    var publishesNowPlaying = false
    var windowCheck = false
    /// Keep the main window on screen (for screenshots); otherwise self-tests
    /// run windowless so they don't get in your way.
    var showsWindow = false

    /// nil unless `--autotest` is present.
    init?(arguments: [String]) {
        guard arguments.contains("--autotest") else { return nil }
        let args = CommandLineArguments(arguments)
        totalSeconds = args.int("--autotest-seconds") ?? totalSeconds
        cycleSeconds = max(2, args.int("--autotest-cycle") ?? cycleSeconds)
        timerMinutes = args.int("--autotest-timer-minutes").flatMap { $0 > 0 ? $0 : nil }
        stopAtSeconds = args.int("--autotest-stop-at") ?? 0
        volume = args.double("--autotest-volume") ?? volume
        programSeconds = args.int("--autotest-program-seconds") ?? 0
        pauseAtSeconds = args.int("--autotest-pause-at") ?? 0
        resumeAtSeconds = args.int("--autotest-resume-at") ?? 0
        deviceChangeAtSeconds = args.int("--autotest-device-change-at") ?? 0
        publishesNowPlaying = arguments.contains("--autotest-now-playing")
        windowCheck = arguments.contains("--autotest-window-check")
        showsWindow = windowCheck || arguments.contains("--autotest-show-window")
    }
}

/// `--name value` / `--name=value` lookup.
struct CommandLineArguments {
    private let arguments: [String]

    init(_ arguments: [String]) {
        self.arguments = arguments
    }

    /// The value of the last occurrence, so later flags override earlier
    /// ones (e.g. a script's defaults followed by AUTOTEST_EXTRA_ARGS).
    func value(_ name: String) -> String? {
        var result: String?
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument.hasPrefix(name + "=") {
                result = String(argument.dropFirst(name.count + 1))
            } else if argument == name, index + 1 < arguments.count {
                result = arguments[index + 1]
                index += 1
            }
            index += 1
        }
        return result
    }

    func int(_ name: String) -> Int? { value(name).flatMap { Int($0) } }
    func double(_ name: String) -> Double? { value(name).flatMap { Double($0) } }
}

/// Drives the real session through presets, styles, noise, volume, timers,
/// programs, stop/restart, pause/resume and simulated device changes, logging
/// a line per event. The run ends with `AUTOTEST_COMPLETE` and a
/// `SWITCH_CHECK` line, then exits the process.
@MainActor
final class AutoTestRunner: SessionSelfTest {
    private struct Config {
        let preset: BrainwavePreset
        let style: ToneStyle
        let noise: Bool
    }

    /// Every preset × style × noise combination, cycled in order.
    private static let configs: [Config] = ToneStyle.allCases.flatMap { style in
        BrainwavePreset.all.flatMap { preset in
            [Config(preset: preset, style: style, noise: false), Config(preset: preset, style: style, noise: true)]
        }
    }

    let options: AutoTestOptions
    private let session: SessionController
    /// Self-tests always drive the real engine.
    private var engine: AudioEngine { session.engine! }
    private var timer: Timer?
    private var configIndex = 0
    private var startedAt = Date()
    private var lastCycle = Date()
    private var stopPerformed = false
    private var timerVerified = false
    private var pausePerformed = false
    private var resumePerformed = false
    private var deviceChangePerformed = false

    init(session: SessionController, options: AutoTestOptions) {
        self.session = session
        self.options = options
    }

    private var isProgramRun: Bool { options.programSeconds > 0 }

    func start() {
        setvbuf(stdout, nil, _IOLBF, 0)
        session.selfTest = self
        startedAt = Date()
        lastCycle = startedAt

        if isProgramRun {
            let third = max(3, options.programSeconds / 3)
            let program = FocusProgram(
                id: "autotest",
                name: "Autotest Program",
                detail: "",
                steps: [
                    .init(preset: BrainwavePreset.byId("relax"), seconds: TimeInterval(third)),
                    .init(preset: BrainwavePreset.byId("focus"), seconds: TimeInterval(third)),
                    .init(preset: BrainwavePreset.byId("peak"), seconds: TimeInterval(options.programSeconds - 2 * third))
                ]
            )
            session.startProgram(program, style: .binaural, volume: options.volume, withNoise: true)
            log("START_PROGRAM -> \(snapshot())")
        } else if let minutes = options.timerMinutes {
            let first = Self.configs[0]
            session.start(preset: first.preset, style: first.style, volume: options.volume, withNoise: first.noise, minutes: minutes)
            log("START_WITH_TIMER \(minutes)m -> \(snapshot())")
        } else {
            applyConfig()
            log("START -> \(snapshot())")
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    // MARK: Hooks called by SessionController

    var publishesNowPlaying: Bool { options.publishesNowPlaying }

    func programStepped(to index: Int, of count: Int, preset: BrainwavePreset) {
        log("PROGRAM_STEP \(index + 1)/\(count) \(preset.name) -> \(snapshot())")
    }

    func remoteCommandIgnored(_ name: String) {
        log("REMOTE_COMMAND_IGNORED \(name)")
    }

    // MARK: Run loop

    private func tick() {
        let elapsed = Date().timeIntervalSince(startedAt)
        let second = Int(elapsed)

        if options.timerMinutes != nil, !timerVerified, !session.isPlaying, !stopPerformed, !isProgramRun {
            timerVerified = true
            log("TIMER_STOP_VERIFIED at \(second)s -> \(snapshot())")
            restartLater(after: "RESTART_AFTER_TIMER", elapsed: elapsed)
        }

        if options.stopAtSeconds > 0, !stopPerformed, !isProgramRun, second >= options.stopAtSeconds {
            stopPerformed = true
            log("MANUAL_STOP at \(options.stopAtSeconds)s -> \(snapshot())")
            session.stop()
            restartLater(after: "RESTART_AFTER_STOP", elapsed: elapsed, nextConfig: true)
        }

        // Cycling continues after stop/restart so the whole matrix is covered.
        if elapsed - lastCycle.timeIntervalSince(startedAt) >= Double(options.cycleSeconds),
           session.isPlaying, !session.isPaused, !isProgramRun {
            lastCycle = Date()
            configIndex += 1
            let config = currentConfig
            if configIndex % 3 == 2 {
                let volume = options.volume * (0.7 + 0.15 * Double(configIndex % 4))
                session.updateLive(volume: volume, noiseEnabled: config.noise)
                log("LIVE_UPDATE volume=\(Float(volume)) noise=\(config.noise)")
            } else {
                applyConfig()
            }
            log("cycle diag -> \(snapshot())")
        }

        if options.pauseAtSeconds > 0, !pausePerformed, second >= options.pauseAtSeconds,
           session.isPlaying, !session.isPaused {
            pausePerformed = true
            session.pausePlayback()
            log("AUTOTEST_PAUSE at \(second)s -> \(snapshot())")
        }

        if options.resumeAtSeconds > 0, !resumePerformed, second >= options.resumeAtSeconds,
           session.isPlaying, session.isPaused {
            resumePerformed = true
            session.resumePlayback()
            log("AUTOTEST_RESUME at \(second)s -> \(snapshot())")
        }

        if options.deviceChangeAtSeconds > 0, !deviceChangePerformed, second >= options.deviceChangeAtSeconds,
           session.isPlaying {
            deviceChangePerformed = true
            // A burst, like a real device switch: must coalesce to one rebuild.
            for _ in 0..<3 { engine.simulateConfigurationChange() }
            log("AUTOTEST_DEVICE_CHANGE at \(second)s -> \(snapshot())")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
                guard let self else { return }
                let ok = self.session.isPlaying && self.engine.deviceRebuilds == 1 && self.engine.diagnostics.gain > 0.9
                self.log("DEVICE_CHECK \(ok ? "ok" : "FAIL") rebuilds=\(self.engine.deviceRebuilds) -> \(self.snapshot())")
            }
        }

        if elapsed >= Double(options.totalSeconds) {
            finish(elapsed: elapsed)
        }
    }

    private func restartLater(after label: String, elapsed: TimeInterval, nextConfig: Bool = false) {
        guard elapsed < Double(options.totalSeconds) - 8 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            if nextConfig { self.configIndex += 1 }
            self.applyConfig()
            self.log("\(label) -> \(self.snapshot())")
        }
    }

    private func finish(elapsed: TimeInterval) {
        timer?.invalidate()
        timer = nil
        session.stop()
        log("AUTOTEST_COMPLETE total=\(Int(elapsed))s -> \(snapshot())")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            // Every requested preset/style change must reach the render
            // thread or be superseded by a newer one; anything else is lost.
            if let self {
                let (requested, coalesced) = self.engine.switchRequests
                let applied = self.engine.diagnostics.switches
                let ok = requested == applied + coalesced
                self.log("SWITCH_CHECK \(ok ? "ok" : "MISMATCH") requested=\(requested) applied=\(applied) coalesced=\(coalesced)")
            }
            exit(0)
        }
    }

    private var currentConfig: Config {
        Self.configs[configIndex % Self.configs.count]
    }

    /// Live crossfade switch while playing, fresh start otherwise — through
    /// the same session calls the UI uses.
    private func applyConfig() {
        let config = currentConfig
        if session.isPlaying {
            session.switchPreset(preset: config.preset, style: config.style, volume: options.volume, withNoise: config.noise)
        } else {
            session.start(preset: config.preset, style: config.style, volume: options.volume, withNoise: config.noise, minutes: nil)
        }
        log("switch -> \(config.preset.name)/\(config.style.rawValue)/noise=\(config.noise) volume=\(options.volume)")
    }

    private func snapshot() -> String {
        let d = engine.diagnostics
        return "frames=\(d.frames) nan=\(d.nan) clips=\(d.clips) switches=\(d.switches) gain=\(String(format: "%.2f", d.gain)) playing=\(session.isPlaying)"
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    func log(_ message: String) {
        print("[autotest \(Self.timestampFormatter.string(from: Date()))] \(message)")
    }
}
