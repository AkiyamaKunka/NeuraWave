import AVFoundation

/// Main-thread only (SessionController, menu bar, notifications on .main).
/// The realtime render path lives in `RealtimeState` and never touches this.
@MainActor
final class AudioEngine {
    /// A session is active (playing or paused); false once stopped.
    private(set) var isPlaying = false

    /// Called on the main thread when the output can't be (re)started after
    /// a device change, so the session can stop instead of "playing" silence.
    var onOutputFailure: (() -> Void)?

    /// How long after stop/pause the output chain is released: the 2 s fade
    /// plus a margin, so the fade is never cut off.
    private static let releaseDelay: TimeInterval = 2.4

    private let engine = AVAudioEngine()
    private let state = RealtimeState()
    private var sourceNode: AVAudioSourceNode?
    /// Sample rate the current node was built for.
    private var nodeSampleRate: Double = 0
    private var stopGeneration = 0
    private var isPaused = false
    private var keepAwakeActivity: NSObjectProtocol?
    /// What to (re)build the output with after a pause or device change.
    private struct Config {
        var preset: BrainwavePreset
        var style: ToneStyle
        var volume: Float
        var noiseEnabled: Bool
    }

    private var lastConfig: Config?
    // Written once in init, read in the nonisolated deinit.
    nonisolated(unsafe) private var configurationObserver: NSObjectProtocol?
    private var pendingRebuild: DispatchWorkItem?
    /// Output-chain rebuilds after device changes (autotest diagnostics).
    private(set) var deviceRebuilds = 0

    init() {
        // Output device / sample-rate changes (AirPods connecting, headphones
        // unplugged, …) stop AVAudioEngine. Rebuild the chain at the new
        // format so an active session keeps playing.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleRebuildAfterConfigurationChange()
            }
        }
    }

    /// Builds the output node on first use and (re)uses it for every later
    /// session. Returns false when no usable output device/format is available.
    @discardableResult
    func start(preset: BrainwavePreset, style: ToneStyle, volume: Float, withNoise noiseEnabled: Bool) -> Bool {
        stopGeneration += 1
        isPaused = false
        lastConfig = Config(preset: preset, style: style, volume: volume, noiseEnabled: noiseEnabled)

        // The system stopped the engine under us (device change during a
        // stop fade): don't reuse that node mid-fade, rebuild from silence.
        if sourceNode != nil, !engine.isRunning {
            teardownNode()
        }

        if sourceNode == nil {
            // Building a fresh chain supersedes any queued device rebuild.
            pendingRebuild?.cancel()
            pendingRebuild = nil
            let output = engine.outputNode
            let sampleRate = output.outputFormat(forBus: 0).sampleRate
            guard sampleRate > 0,
                  let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
                return false
            }
            // Safe: no node is attached, so no render callback can be running
            // (resetGain writes render-owned state).
            state.resetGain()
            let node = Self.makeSourceNode(format: format, sampleRate: sampleRate, state: state)
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            sourceNode = node
            nodeSampleRate = sampleRate
            requestLargeIOBuffer()
        }

        state.configure(preset: preset, style: style, volume: volume, noiseEnabled: noiseEnabled)
        state.setRunning(true)
        // Publishing Now Playing info briefly marks the app "inactive" on
        // macOS; with auto-shutdown enabled the engine suspends itself and
        // rendering freezes. Keep it alive — we teardown explicitly on stop.
        engine.isAutoShutdownEnabled = false
        engine.prepare()

        do {
            try engine.start()
        } catch {
            state.setRunning(false)
            return false
        }

        beginKeepAwake()
        isPlaying = true
        return true
    }

    /// Built outside the main actor on purpose: the render block runs on the
    /// realtime audio thread and must not inherit main-actor isolation.
    private nonisolated static func makeSourceNode(
        format: AVAudioFormat,
        sampleRate: Double,
        state: RealtimeState
    ) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            state.render(
                buffers: UnsafeMutableAudioBufferListPointer(audioBufferList),
                frameCount: Int(frameCount),
                sampleRate: sampleRate
            )
            return noErr
        }
    }

    /// Live parameter change without rebuilding the node: the render thread
    /// crossfades through silence, so switching is click-free.
    func switchTo(preset: BrainwavePreset, style: ToneStyle, volume: Float, withNoise noiseEnabled: Bool) {
        lastConfig = Config(preset: preset, style: style, volume: volume, noiseEnabled: noiseEnabled)
        state.configure(preset: preset, style: style, volume: volume, noiseEnabled: noiseEnabled)
    }

    func stop() {
        state.setRunning(false)
        isPlaying = false
        isPaused = false
        endKeepAwake()

        // Let the fade-out finish (~2s) before tearing the node down. A newer
        // start() bumps stopGeneration, so this can never kill a live session.
        let generation = stopGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.releaseDelay) { [weak self] in
            guard let self, self.stopGeneration == generation else { return }
            self.teardownNode()
            self.isPlaying = false
        }
    }

    func update(volume: Float, noiseEnabled: Bool) {
        lastConfig?.volume = volume
        lastConfig?.noiseEnabled = noiseEnabled
        state.update(volume: volume, noiseEnabled: noiseEnabled)
    }

    /// Pause keeps the session alive: the render thread fades the gain to
    /// zero, then the output chain is released so a paused session neither
    /// burns CPU rendering silence nor keeps the Mac awake.
    func pause() {
        state.setRunning(false)
        isPaused = true
        endKeepAwake()
        let generation = stopGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.releaseDelay) { [weak self] in
            guard let self, self.isPaused, self.stopGeneration == generation else { return }
            self.teardownNode()
        }
    }

    /// Full output-chain restart: tears down and rebuilds the audio route,
    /// clearing any system-level mute/route state that may have been applied
    /// while the app was paused. Fades back in from silence. Returns false
    /// when the output can't be started (e.g. the device went away).
    @discardableResult
    func restartAfterPause() -> Bool {
        if sourceNode != nil, engine.isRunning {
            // Resumed before the pause released the chain (and the device is
            // still there): just ramp back up from wherever the fade-out got
            // to. Tearing down mid-fade would cut the signal — a click.
            stopGeneration += 1 // cancels the pending pause teardown
            isPaused = false
            state.setRunning(true)
            beginKeepAwake()
            isPlaying = true
            return true
        }
        teardownNode()
        guard let cfg = lastConfig else { return false }
        return start(preset: cfg.preset, style: cfg.style, volume: cfg.volume, withNoise: cfg.noiseEnabled)
    }

    /// Something may still be coming out of the speakers (including the
    /// tail of a stop fade), so quitting now would click.
    var isAudible: Bool {
        sourceNode != nil && engine.isRunning && state.diagnostics().gain > 0.001
    }

    var diagnostics: (frames: UInt64, nan: UInt64, clips: UInt64, switches: UInt64, gain: Float) {
        state.diagnostics()
    }

    /// Every request is either applied by the render thread or superseded by
    /// a newer one before it could be; anything else was lost.
    var switchRequests: (requested: UInt64, coalesced: UInt64) {
        state.requests()
    }

    /// A device switch usually fires several notifications in a row (and our
    /// own rebuild may add one); coalesce them into a single rebuild.
    private func scheduleRebuildAfterConfigurationChange() {
        pendingRebuild?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingRebuild = nil
            self?.handleConfigurationChange()
        }
        pendingRebuild = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    /// Autotest hook: behave exactly as if the output device had changed.
    func simulateConfigurationChange() {
        // A real device switch stops the engine before notifying.
        engine.stop()
        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: engine)
    }

    private func handleConfigurationChange() {
        // Only an active session needs the chain back. A paused one is rebuilt
        // on resume anyway; idle has nothing to restore.
        guard isPlaying, !isPaused, sourceNode != nil, let cfg = lastConfig else { return }
        // Nothing actually changed for us (e.g. the notification our own
        // rebuild can trigger): rebuilding again would cut the fade-in and,
        // worst case, loop forever.
        if engine.isRunning, engine.outputNode.outputFormat(forBus: 0).sampleRate == nodeSampleRate {
            return
        }
        deviceRebuilds += 1
        teardownNode()
        if !start(preset: cfg.preset, style: cfg.style, volume: cfg.volume, withNoise: cfg.noiseEnabled) {
            isPlaying = false
            onOutputFailure?()
        }
    }

    /// Steady tones don't need low latency: a ~43 ms IO buffer (2048 frames
    /// at 48 kHz) instead of the default ~11 ms means a quarter of the audio
    /// wakeups, for less CPU and energy. Switches and pauses are fades of
    /// 60 ms or more anyway. Best effort: the device may clamp or refuse it.
    private func requestLargeIOBuffer() {
        guard let unit = engine.outputNode.audioUnit else { return }
        var frames: UInt32 = 2048
        AudioUnitSetProperty(
            unit,
            kAudioDevicePropertyBufferFrameSize,
            kAudioUnitScope_Global,
            0,
            &frames,
            UInt32(MemoryLayout<UInt32>.size)
        )
    }

    private func beginKeepAwake() {
        guard keepAwakeActivity == nil else { return }
        keepAwakeActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "NeuraWave brainwave audio session"
        )
    }

    private func endKeepAwake() {
        if let activity = keepAwakeActivity {
            ProcessInfo.processInfo.endActivity(activity)
            keepAwakeActivity = nil
        }
    }

    /// Releases the output chain. Session state (isPlaying/isPaused) is the
    /// caller's business, so a paused session survives its node going away.
    private func teardownNode() {
        engine.stop()
        if let node = sourceNode {
            engine.disconnectNodeOutput(node)
            engine.detach(node)
            sourceNode = nil
        }
        endKeepAwake()
    }

    deinit {
        // AVAudioEngine stops itself when released; only the observer needs
        // explicit removal. (The app-wide instance lives for the whole run.)
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
    }
}
