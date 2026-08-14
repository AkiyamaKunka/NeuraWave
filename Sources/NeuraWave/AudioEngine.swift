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
private final class RealtimeState: @unchecked Sendable {
    private struct Config {
        var carrier: Double
        var beat: Double
        var style: ToneStyle
        var volume: Float
        var noiseEnabled: Bool
    }

    private let lock = OSAllocatedUnfairLock()
    private var config = Config(carrier: 240, beat: 10, style: .binaural, volume: 0.55, noiseEnabled: false)
    private var pendingConfig: Config?
    private var running = false
    private var gain: Float = 0
    private var quickRamp = false
    private var phaseLeft: Double = 0
    private var phaseRight: Double = 0
    private var envelopePhase: Double = 0
    private var noiseRows = [Float](repeating: 0, count: 16)
    private var framesRendered: UInt64 = 0
    private var nanCount: UInt64 = 0
    private var clipCount: UInt64 = 0
    private var switchCount: UInt64 = 0

    // Gain-ramp durations: slow fade for start/stop, quick dip for live switches.
    private let startStopFadeSeconds = 2.0
    private let crossfadeDownSeconds = 0.06
    private let crossfadeUpSeconds = 0.15

    /// Request a new configuration. If audio is currently audible the change is
    /// queued and the render thread dips to silence, swaps parameters (phases
    /// reset while inaudible), and ramps back up — no node rebuild, no click.
    func configure(preset: BrainwavePreset, style: ToneStyle, volume: Float, noiseEnabled: Bool) {
        let next = Config(carrier: preset.carrier, beat: preset.beat, style: style, volume: volume, noiseEnabled: noiseEnabled)
        lock.withLock {
            if gain > 0.001 {
                pendingConfig = next
            } else {
                applyConfig(next)
            }
        }
    }

    func setRunning(_ value: Bool) {
        lock.withLock { running = value }
    }

    func update(volume: Float, noiseEnabled: Bool) {
        lock.withLock {
            config.volume = volume
            config.noiseEnabled = noiseEnabled
            if pendingConfig != nil {
                pendingConfig!.volume = volume
                pendingConfig!.noiseEnabled = noiseEnabled
            }
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
        var config = self.config
        var pending = self.pendingConfig
        let running = self.running
        var gain = self.gain
        var quickRamp = self.quickRamp
        var phaseLeft = self.phaseLeft
        var phaseRight = self.phaseRight
        var envelopePhase = self.envelopePhase
        var noiseRows = self.noiseRows
        lock.unlock()

        let twoPi = 2.0 * Double.pi
        let slowFadeFrames = Float(sampleRate * startStopFadeSeconds)
        let quickDownFrames = Float(sampleRate * crossfadeDownSeconds)
        let quickUpFrames = Float(sampleRate * crossfadeUpSeconds)
        var nanCount = 0
        var clipCount = 0
        var switchesApplied = 0

        for i in 0..<frameCount {
            // Crossfade state machine: when a pending config exists, ramp to
            // silence first; once silent, swap parameters and head back up.
            if let pendingConfig = pending, gain <= 0.001 {
                config = pendingConfig
                pending = nil
                phaseLeft = 0
                phaseRight = 0
                envelopePhase = 0
                quickRamp = true
                switchesApplied += 1
            }

            var target: Float = running ? 1 : 0
            if pending != nil && gain > 0.001 {
                target = 0
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

            let stepLeft = twoPi * config.carrier / sampleRate
            let stepRight = twoPi * (config.carrier + (config.style == .binaural ? config.beat : 0)) / sampleRate
            let envelopeStep = twoPi * config.beat / sampleRate

            let envelope: Float
            if config.style == .isochronic {
                envelope = 0.45 + 0.55 * Float(0.5 + 0.5 * sin(envelopePhase))
            } else {
                envelope = 1
            }

            let toneLevel = 0.36 * config.volume
            let noiseLevel = 0.10 * config.volume * (config.noiseEnabled ? 1 : 0)
            let tone = toneLevel * envelope * gain
            let leftSample = Float(sin(phaseLeft)) * tone
            let rightSample = Float(sin(phaseRight)) * tone

            var noise: Float = 0
            if config.noiseEnabled {
                let row = Int.random(in: 0..<noiseRows.count)
                noiseRows[row] = Float.random(in: -1...1)
                noise = noiseRows.reduce(0, +) / Float(noiseRows.count)
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

            phaseLeft += stepLeft
            phaseRight += stepRight
            envelopePhase += envelopeStep
            if phaseLeft > twoPi { phaseLeft -= twoPi }
            if phaseRight > twoPi { phaseRight -= twoPi }
            if envelopePhase > twoPi { envelopePhase -= twoPi }
        }

        lock.lock()
        self.config = config
        self.pendingConfig = pending
        self.gain = gain
        self.quickRamp = quickRamp
        self.phaseLeft = phaseLeft
        self.phaseRight = phaseRight
        self.envelopePhase = envelopePhase
        self.noiseRows = noiseRows
        self.framesRendered += UInt64(frameCount)
        self.nanCount += UInt64(nanCount)
        self.clipCount += UInt64(clipCount)
        self.switchCount += UInt64(switchesApplied)
        lock.unlock()
    }

    func diagnostics() -> (frames: UInt64, nan: UInt64, clips: UInt64, switches: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        return (framesRendered, nanCount, clipCount, switchCount)
    }

    private func applyConfig(_ next: Config) {
        config = next
        phaseLeft = 0
        phaseRight = 0
        envelopePhase = 0
    }
}

final class AudioEngine: ObservableObject {
    @Published private(set) var isPlaying = false

    private let engine = AVAudioEngine()
    private let state = RealtimeState()
    private var sourceNode: AVAudioSourceNode?
    private var stopGeneration = 0
    private var keepAwakeActivity: NSObjectProtocol?

    /// Builds the output node on first use and (re)uses it for every later
    /// session. Returns false when no usable output device/format is available.
    @discardableResult
    func start(preset: BrainwavePreset, style: ToneStyle, volume: Float, withNoise noiseEnabled: Bool) -> Bool {
        stopGeneration += 1

        if sourceNode == nil {
            let output = engine.outputNode
            let sampleRate = output.outputFormat(forBus: 0).sampleRate
            guard sampleRate > 0,
                  let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
                return false
            }
            let node = AVAudioSourceNode(format: format) { [state] _, _, frameCount, audioBufferList -> OSStatus in
                state.render(
                    buffers: UnsafeMutableAudioBufferListPointer(audioBufferList),
                    frameCount: Int(frameCount),
                    sampleRate: sampleRate
                )
                return noErr
            }
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            sourceNode = node
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

        if keepAwakeActivity == nil {
            keepAwakeActivity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleSystemSleepDisabled],
                reason: "NeuraWave brainwave audio session"
            )
        }
        isPlaying = true
        return true
    }

    /// Live parameter change without rebuilding the node: the render thread
    /// crossfades through silence, so switching is click-free.
    func switchTo(preset: BrainwavePreset, style: ToneStyle, volume: Float, withNoise noiseEnabled: Bool) {
        state.configure(preset: preset, style: style, volume: volume, noiseEnabled: noiseEnabled)
    }

    func stop() {
        state.setRunning(false)
        isPlaying = false
        if let activity = keepAwakeActivity {
            ProcessInfo.processInfo.endActivity(activity)
            keepAwakeActivity = nil
        }

        // Let the fade-out finish (~2s) before tearing the node down. A newer
        // start() bumps stopGeneration, so this can never kill a live session.
        let generation = stopGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
            guard let self, self.stopGeneration == generation else { return }
            self.teardownNode()
        }
    }

    func update(volume: Float, noiseEnabled: Bool) {
        state.update(volume: volume, noiseEnabled: noiseEnabled)
    }

    /// Pause/resume keep the session alive: the render thread fades the gain
    /// to zero and back, so AirPods toggles are click-free.
    func pause() {
        state.setRunning(false)
    }

    func resume() {
        state.setRunning(true)
    }

    var diagnostics: (frames: UInt64, nan: UInt64, clips: UInt64, switches: UInt64) {
        state.diagnostics()
    }

    private func teardownNode() {
        engine.stop()
        if let node = sourceNode {
            engine.disconnectNodeOutput(node)
            engine.detach(node)
            sourceNode = nil
        }
        if let activity = keepAwakeActivity {
            ProcessInfo.processInfo.endActivity(activity)
            keepAwakeActivity = nil
        }
        isPlaying = false
    }

    deinit {
        teardownNode()
    }
}
