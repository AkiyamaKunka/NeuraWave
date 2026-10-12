import AVFoundation
import os

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
