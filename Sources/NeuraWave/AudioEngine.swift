import AVFoundation
import Combine
import os

enum ToneStyle: String, CaseIterable, Identifiable {
    case binaural = "Binaural"
    case isochronic = "Isochronic"

    var id: String { rawValue }

    var tip: String {
        switch self {
        case .binaural:
            return "Two tones, one per ear · headphones recommended"
        case .isochronic:
            return "Pulsing single tone · works with speakers"
        }
    }
}

/// Mutable state shared with the realtime audio thread.
///
/// Ownership rules (they are what keeps updates from being lost):
/// - The main thread owns `running`, `volume`, `noiseEnabled` and
///   `pendingTone`; the render thread only reads them (and *takes*
///   `pendingTone` under the lock).
/// - The render thread owns `tone`, `gain`, the oscillators, the noise generator
///   and the counters; the main thread only reads them.
/// The render callback therefore never writes back a field another thread may
/// have changed while it was rendering.
final class RealtimeState: @unchecked Sendable {
    /// Per-sample phasor rotations for the current tone.
    private struct Rotations {
        let left: Rotation
        let right: Rotation
        let envelope: Rotation

        init(tone: ToneConfig, sampleRate: Double) {
            left = Rotation(frequency: tone.carrier, sampleRate: sampleRate)
            right = Rotation(frequency: tone.carrier + (tone.style == .binaural ? tone.beat : 0), sampleRate: sampleRate)
            envelope = Rotation(frequency: tone.beat, sampleRate: sampleRate)
        }
    }

    private struct ToneConfig {
        var carrier: Double
        var beat: Double
        var style: ToneStyle
    }

    private let lock = OSAllocatedUnfairLock()
    // Main-thread owned.
    private var pendingTone: ToneConfig?
    private var running = false
    private var volume: Float = 0.385
    private var noiseEnabled = false
    private var requestCount: UInt64 = 0
    /// Requests superseded by a newer one before the render thread applied
    /// them (two changes within one crossfade dip). Intentional, not lost.
    private var coalescedCount: UInt64 = 0
    // Render-thread owned.
    private var tone = ToneConfig(carrier: 240, beat: 10, style: .binaural)
    private var gain: Float = 0
    /// Per-sample smoothed levels, so dragging the volume slider or toggling
    /// noise glides instead of stepping (no zipper noise / clicks).
    private var smoothedVolume: Float = 0.385
    private var smoothedNoise: Float = 0
    private var levelsPrimed = false
    private var quickRamp = false
    /// True while the gain is being dipped to silence for a live switch, so
    /// the swap is followed by the quick ramp back up. A request applied from
    /// silence (session start, resume) keeps the slow, gentle fade-in.
    private var switchDip = false
    private var left = SineOscillator()
    private var right = SineOscillator()
    private var envelopeOscillator = SineOscillator()
    private var framesRendered: UInt64 = 0
    private var nanCount: UInt64 = 0
    private var clipCount: UInt64 = 0
    private var switchCount: UInt64 = 0
    /// Smoothed noise source: a fixed, preallocated buffer (no allocation on
    /// the audio thread) with a running sum and a cheap inline PRNG.
    private static let noiseRowCount = 16
    private let noiseRows = UnsafeMutablePointer<Float>.allocate(capacity: noiseRowCount)
    private var noiseSum: Float = 0
    private var rngState: UInt32 = 0x9E37_79B9

    // Gain-ramp durations: slow fade for start/stop, quick dip for live switches.
    private let startStopFadeSeconds = 2.0
    private let crossfadeDownSeconds = 0.06
    private let crossfadeUpSeconds = 0.15

    init() {
        noiseRows.initialize(repeating: 0, count: Self.noiseRowCount)
    }

    deinit {
        noiseRows.deallocate()
    }

    /// Request a new configuration. The render thread applies it once the
    /// output is silent: if audio is audible it first dips to silence, swaps
    /// parameters (phases reset while inaudible), and ramps back up — no node
    /// rebuild, no click.
    func configure(preset: BrainwavePreset, style: ToneStyle, volume: Float, noiseEnabled: Bool) {
        lock.withLock {
            if pendingTone != nil {
                coalescedCount += 1
            }
            pendingTone = ToneConfig(carrier: preset.carrier, beat: preset.beat, style: style)
            requestCount += 1
            self.volume = volume
            self.noiseEnabled = noiseEnabled
        }
    }

    func setRunning(_ value: Bool) {
        lock.withLock { running = value }
    }

    func update(volume: Float, noiseEnabled: Bool) {
        lock.withLock {
            self.volume = volume
            self.noiseEnabled = noiseEnabled
        }
    }

    /// Called only while no render callback can run (node detached), so a
    /// rebuilt node fades in from silence instead of starting at full level.
    func resetGain() {
        lock.withLock {
            gain = 0
            quickRamp = false
            switchDip = false
        }
    }

    func render(
        buffers: UnsafeMutableAudioBufferListPointer,
        frameCount: Int,
        sampleRate: Double
    ) {
        guard buffers.count >= 2,
              let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
              let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else {
            return
        }

        lock.lock()
        var tone = self.tone
        // Take ownership of the pending request; if it is not applied in this
        // buffer it is handed back below (unless a newer one arrived).
        var pending = self.pendingTone
        self.pendingTone = nil
        let running = self.running
        let volume = self.volume
        let noiseEnabled = self.noiseEnabled
        var gain = self.gain
        var smoothedVolume = self.smoothedVolume
        var smoothedNoise = self.smoothedNoise
        if !self.levelsPrimed {
            // First buffer ever: start at the requested level, don't glide in.
            smoothedVolume = volume
            smoothedNoise = noiseEnabled ? 1 : 0
            self.levelsPrimed = true
        }
        var quickRamp = self.quickRamp
        var switchDip = self.switchDip
        var leftOscillator = self.left
        var rightOscillator = self.right
        var envelopeOscillator = self.envelopeOscillator
        lock.unlock()

        var rotations = Rotations(tone: tone, sampleRate: sampleRate)
        let slowFadeFrames = Float(sampleRate * startStopFadeSeconds)
        let quickDownFrames = Float(sampleRate * crossfadeDownSeconds)
        let quickUpFrames = Float(sampleRate * crossfadeUpSeconds)
        let rowCount = Self.noiseRowCount
        // ~25 ms one-pole glide toward the requested levels.
        let smoothing = Float(1 - exp(-1 / (sampleRate * 0.025)))
        let noiseTarget: Float = noiseEnabled ? 1 : 0
        var nanCount = 0
        var clipCount = 0
        var switchesApplied = 0

        for i in 0..<frameCount {
            // Crossfade state machine: when a pending config exists, ramp to
            // silence first; once silent, swap parameters and head back up.
            if let pendingTone = pending, gain <= 0.001 {
                tone = pendingTone
                pending = nil
                rotations = Rotations(tone: tone, sampleRate: sampleRate)
                leftOscillator.reset()
                rightOscillator.reset()
                envelopeOscillator.reset()
                quickRamp = switchDip
                switchDip = false
                switchesApplied += 1
            }

            var target: Float = running ? 1 : 0
            if pending != nil && gain > 0.001 {
                target = 0
                switchDip = true
            }

            let fadeFrames: Float
            if pending != nil {
                fadeFrames = quickDownFrames
            } else if quickRamp {
                fadeFrames = quickUpFrames
            } else {
                fadeFrames = slowFadeFrames
            }
            let step = 1.0 / max(fadeFrames, 1)
            if gain < target {
                gain = min(target, gain + step)
            } else if gain > target {
                gain = max(target, gain - step)
            }
            if abs(gain - target) <= step {
                quickRamp = false
            }

            let envelopeValue = envelopeOscillator.next(rotations.envelope)
            let envelope: Float
            if tone.style == .isochronic {
                envelope = 0.45 + 0.55 * Float(0.5 + 0.5 * envelopeValue)
            } else {
                envelope = 1
            }

            smoothedVolume += (volume - smoothedVolume) * smoothing
            smoothedNoise += (noiseTarget - smoothedNoise) * smoothing
            let toneLevel = 0.36 * smoothedVolume
            let noiseLevel = 0.10 * smoothedVolume * smoothedNoise
            let toneSample = toneLevel * envelope * gain
            let leftSample = Float(leftOscillator.next(rotations.left)) * toneSample
            let rightSample = Float(rightOscillator.next(rotations.right)) * toneSample

            var noise: Float = 0
            if smoothedNoise > 0.0001 {
                // xorshift32: allocation- and syscall-free, fine for noise.
                rngState ^= rngState << 13
                rngState ^= rngState >> 17
                rngState ^= rngState << 5
                let row = Int(rngState % UInt32(rowCount))
                let value = Float(rngState >> 8) / Float(1 << 23) - 1
                noiseSum += value - noiseRows[row]
                noiseRows[row] = value
                noise = noiseSum / Float(rowCount)
            }

            let noiseSample = noise * noiseLevel * gain
            var leftOutput = leftSample + noiseSample
            var rightOutput = rightSample + noiseSample
            if leftOutput.isNaN || rightOutput.isNaN {
                nanCount += 1
                if leftOutput.isNaN { leftOutput = 0 }
                if rightOutput.isNaN { rightOutput = 0 }
            }
            if abs(leftOutput) > 1 || abs(rightOutput) > 1 {
                clipCount += 1
            }
            left[i] = max(-1, min(1, leftOutput))
            right[i] = max(-1, min(1, rightOutput))

        }
        // Keep the phasors on the unit circle (rounding drift is ~1e-16 per
        // sample, so once per buffer is plenty).
        leftOscillator.renormalize()
        rightOscillator.renormalize()
        envelopeOscillator.renormalize()

        lock.lock()
        self.tone = tone
        if self.pendingTone == nil {
            // Still mid-dip: keep the request for the next buffer.
            self.pendingTone = pending
        } else if pending != nil {
            // A request that arrived during this render is newer and wins;
            // the one this render was still holding is superseded.
            self.coalescedCount += 1
        }
        self.gain = gain
        self.smoothedVolume = smoothedVolume
        self.smoothedNoise = smoothedNoise
        self.quickRamp = quickRamp
        self.switchDip = switchDip
        self.left = leftOscillator
        self.right = rightOscillator
        self.envelopeOscillator = envelopeOscillator
        self.framesRendered += UInt64(frameCount)
        self.nanCount += UInt64(nanCount)
        self.clipCount += UInt64(clipCount)
        self.switchCount += UInt64(switchesApplied)
        lock.unlock()
    }

    /// Configuration requests made so far (autotest compares this with the
    /// number of switches the render thread actually applied).
    func requests() -> (requested: UInt64, coalesced: UInt64) {
        lock.withLock { (requestCount, coalescedCount) }
    }

    func diagnostics() -> (frames: UInt64, nan: UInt64, clips: UInt64, switches: UInt64, gain: Float) {
        lock.lock()
        defer { lock.unlock() }
        return (framesRendered, nanCount, clipCount, switchCount, gain)
    }
}

/// Main-thread only (SessionController, menu bar, notifications on .main).
/// The realtime render path lives in `RealtimeState` and never touches this.
@MainActor
final class AudioEngine: ObservableObject {
    @Published private(set) var isPlaying = false

    /// Called on the main thread when the output can't be (re)started after
    /// a device change, so the session can stop instead of "playing" silence.
    var onOutputFailure: (() -> Void)?

    private let engine = AVAudioEngine()
    private let state = RealtimeState()
    private var sourceNode: AVAudioSourceNode?
    /// Sample rate the current node was built for.
    private var nodeSampleRate: Double = 0
    private var stopGeneration = 0
    private var isPaused = false
    private var keepAwakeActivity: NSObjectProtocol?
    private var lastConfig: (preset: BrainwavePreset, style: ToneStyle, volume: Float, noiseEnabled: Bool)?
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
        lastConfig = (preset, style, volume, noiseEnabled)

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
            state.resetGain()
            let node = Self.makeSourceNode(format: format, sampleRate: sampleRate, state: state)
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            sourceNode = node
            nodeSampleRate = sampleRate
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
        lastConfig = (preset, style, volume, noiseEnabled)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
            guard let self, self.stopGeneration == generation else { return }
            self.teardownNode()
            self.isPlaying = false
        }
    }

    func update(volume: Float, noiseEnabled: Bool) {
        if let cfg = lastConfig {
            lastConfig = (cfg.preset, cfg.style, volume, noiseEnabled)
        }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
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

/// Phase advance per sample for one frequency, as a rotation.
struct Rotation {
    let cos: Double
    let sin: Double

    init(frequency: Double, sampleRate: Double) {
        let step = 2 * Double.pi * frequency / sampleRate
        cos = Foundation.cos(step)
        sin = Foundation.sin(step)
    }
}

/// Sine generator that rotates a unit phasor: one complex multiply per
/// sample instead of a sin() call, phase-continuous across buffers. Starts
/// at phase 0 (value 0) like a freshly reset phase accumulator.
struct SineOscillator {
    private var s: Double = 0 // sin(phase)
    private var c: Double = 1 // cos(phase)

    mutating func reset() {
        s = 0
        c = 1
    }

    /// The current sample, then advance one step.
    @inline(__always)
    mutating func next(_ rotation: Rotation) -> Double {
        let value = s
        let nextS = s * rotation.cos + c * rotation.sin
        c = c * rotation.cos - s * rotation.sin
        s = nextS
        return value
    }

    /// Pull the phasor back onto the unit circle (call once per buffer).
    mutating func renormalize() {
        let magnitude = (s * s + c * c).squareRoot()
        guard magnitude > 0 else {
            reset()
            return
        }
        s /= magnitude
        c /= magnitude
    }
}
