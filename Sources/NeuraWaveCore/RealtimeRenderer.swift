import AVFoundation
import os

/// Mutable state shared with the realtime audio thread.
///
/// Ownership rules (they are what keeps updates from being lost):
/// - The main thread owns `running`, `volume`, `noiseEnabled` and
///   `pendingTone`; the render thread only reads them (and *takes*
///   `pendingTone` under the lock).
/// - The render thread owns the voice, fader, level smoother, noise
///   generator and counters; the main thread only reads diagnostics.
/// The render callback therefore never writes back a field another thread may
/// have changed while it was rendering.
public final class RealtimeState: @unchecked Sendable {
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
    private var voice = Voice()
    private var fader = GainFader()
    private var levels: LevelSmoother?
    private var noiseGenerator = NoiseGenerator()
    private var framesRendered: UInt64 = 0
    private var nanCount: UInt64 = 0
    private var clipCount: UInt64 = 0
    private var switchCount: UInt64 = 0

    /// Request a new configuration. The render thread applies it once the
    /// output is silent: if audio is audible it first dips to silence, swaps
    /// parameters (phases reset while inaudible), and ramps back up — no node
    /// rebuild, no click.
    public func configure(preset: BrainwavePreset, style: ToneStyle, volume: Float, noiseEnabled: Bool) {
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

    public func setRunning(_ value: Bool) {
        lock.withLock { running = value }
    }

    public func update(volume: Float, noiseEnabled: Bool) {
        lock.withLock {
            self.volume = volume
            self.noiseEnabled = noiseEnabled
        }
    }

    /// Called only while no render callback can run (node detached), so a
    /// rebuilt node fades in from silence instead of starting at full level.
    /// This is the one main-thread write to render-owned state; calling it
    /// while a node is attached would race with render().
    public func resetGain() {
        lock.withLock { fader = GainFader() }
    }

    public func render(
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
        // Take ownership of the pending request; if it is not applied in this
        // buffer it is handed back below (unless a newer one arrived).
        var pending = pendingTone
        pendingTone = nil
        let running = self.running
        let volume = self.volume
        let noiseEnabled = self.noiseEnabled
        lock.unlock()

        // Render-owned state: work on local copies, write back at the end.
        var voice = self.voice
        var fader = self.fader
        // First buffer ever: start at the requested levels, don't glide in.
        var levels = self.levels ?? LevelSmoother(volume: volume, noise: noiseEnabled ? 1 : 0)
        var noiseGenerator = self.noiseGenerator
        voice.prepare(sampleRate: sampleRate)
        let fades = GainFader.Rates(sampleRate: sampleRate)
        let smoothing = LevelSmoother.coefficient(sampleRate: sampleRate)
        let noiseTarget: Float = noiseEnabled ? 1 : 0
        var nanCount = 0
        var clipCount = 0
        var switchesApplied = 0

        for i in 0..<frameCount {
            // Crossfade: with a request pending, dip to silence first; once
            // silent, retune (phases restart inaudibly) and head back up.
            if let next = pending, fader.isSilent {
                voice.retune(to: next, sampleRate: sampleRate)
                fader.didSwitch()
                pending = nil
                switchesApplied += 1
            }
            let gain = fader.advance(running: running, switching: pending != nil, rates: fades)
            levels.advance(volume: volume, noise: noiseTarget, coefficient: smoothing)

            let (leftTone, rightTone) = voice.next()
            let toneSample = 0.36 * levels.volume * gain
            let noise: Float = levels.noise > 0.0001 ? noiseGenerator.next() : 0
            let noiseSample = noise * 0.10 * levels.volume * levels.noise * gain

            var leftOutput = leftTone * toneSample + noiseSample
            var rightOutput = rightTone * toneSample + noiseSample
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
        voice.renormalize()
        noiseGenerator.resync()

        lock.lock()
        if pendingTone == nil {
            // Still mid-dip: keep the request for the next buffer.
            pendingTone = pending
        } else if pending != nil {
            // A request that arrived during this render is newer and wins;
            // the one this render was still holding is superseded.
            coalescedCount += 1
        }
        self.voice = voice
        self.fader = fader
        self.levels = levels
        self.noiseGenerator = noiseGenerator
        framesRendered += UInt64(frameCount)
        self.nanCount += UInt64(nanCount)
        self.clipCount += UInt64(clipCount)
        switchCount += UInt64(switchesApplied)
        lock.unlock()
    }

    /// Configuration requests made so far (autotest compares this with the
    /// number of switches the render thread actually applied).
    public func requests() -> (requested: UInt64, coalesced: UInt64) {
        lock.withLock { (requestCount, coalescedCount) }
    }

    public func diagnostics() -> (frames: UInt64, nan: UInt64, clips: UInt64, switches: UInt64, gain: Float) {
        lock.lock()
        defer { lock.unlock() }
        return (framesRendered, nanCount, clipCount, switchCount, fader.gain)
    }
}

/// The tone being played.
public struct ToneConfig: Sendable {
    public var carrier: Double
    public var beat: Double
    public var style: ToneStyle

    /// Right-ear frequency: offset by the beat for binaural, same as the
    /// left for isochronic (which pulses instead).
    public var rightFrequency: Double {
        carrier + (style == .binaural ? beat : 0)
    }
}

/// What is sounding: the tone and its three oscillators (left carrier, right
/// carrier, isochronic pulse envelope). Produces the unscaled stereo tone.
public struct Voice: Sendable {
    public private(set) var tone = ToneConfig(carrier: 240, beat: 10, style: .binaural)
    private var left = SineOscillator()
    private var right = SineOscillator()
    private var envelope = SineOscillator()
    private var rotations: (left: Rotation, right: Rotation, envelope: Rotation)?
    private var preparedSampleRate: Double = 0

    /// Make sure the per-sample rotations match `sampleRate` (cheap no-op
    /// unless the device rate or tone changed).
    public mutating func prepare(sampleRate: Double) {
        guard rotations == nil || preparedSampleRate != sampleRate else { return }
        preparedSampleRate = sampleRate
        rotations = (
            Rotation(frequency: tone.carrier, sampleRate: sampleRate),
            Rotation(frequency: tone.rightFrequency, sampleRate: sampleRate),
            Rotation(frequency: tone.beat, sampleRate: sampleRate)
        )
    }

    /// Switch tone, restarting every oscillator at phase 0. Call while silent.
    public mutating func retune(to tone: ToneConfig, sampleRate: Double) {
        self.tone = tone
        rotations = nil
        prepare(sampleRate: sampleRate)
        left.reset()
        right.reset()
        envelope.reset()
    }

    /// Next stereo tone sample in [-1, 1] (before volume and fades).
    @inline(__always)
    public mutating func next() -> (left: Float, right: Float) {
        guard let rotations else { return (0, 0) }
        let pulse = envelope.next(rotations.envelope)
        // Isochronic: the tone pulses between 45% and 100% at the beat rate.
        let level: Float = tone.style == .isochronic ? 0.45 + 0.55 * Float(0.5 + 0.5 * pulse) : 1
        return (Float(left.next(rotations.left)) * level, Float(right.next(rotations.right)) * level)
    }

    /// Keep the oscillators exact (call once per buffer).
    public mutating func renormalize() {
        left.renormalize()
        right.renormalize()
        envelope.renormalize()
    }
}

/// The start/stop fade and the click-free switch dip, one sample at a time.
///
/// - Start/stop and pause/resume fade slowly (2 s).
/// - A live switch dips to silence quickly (60 ms), the tone is swapped while
///   silent, then it comes back quickly (150 ms).
/// - A tone applied from silence (session start) keeps the slow fade-in.
public struct GainFader: Sendable {
    public struct Rates: Sendable {
        public let slowStep: Float
        public let dipStep: Float
        public let recoverStep: Float

        public init(sampleRate: Double) {
            slowStep = 1 / max(Float(sampleRate * 2.0), 1)
            dipStep = 1 / max(Float(sampleRate * 0.06), 1)
            recoverStep = 1 / max(Float(sampleRate * 0.15), 1)
        }
    }

    public private(set) var gain: Float = 0
    /// Ramp up quickly: the last switch was a dip from audible.
    private var quickRecovery = false
    /// Currently dipping for a live switch (gain was audible when it began).
    private var dipping = false

    public var isSilent: Bool { gain <= 0.001 }

    /// The pending tone was applied while silent.
    public mutating func didSwitch() {
        quickRecovery = dipping
        dipping = false
    }

    /// Advance one sample toward silence (stopped/paused, or dipping for a
    /// switch) or full level; returns the new gain.
    @inline(__always)
    public mutating func advance(running: Bool, switching: Bool, rates: Rates) -> Float {
        var target: Float = running ? 1 : 0
        if switching && !isSilent {
            target = 0
            dipping = true
        }
        let step = switching ? rates.dipStep : (quickRecovery ? rates.recoverStep : rates.slowStep)
        if gain < target {
            gain = min(target, gain + step)
        } else if gain > target {
            gain = max(target, gain - step)
        }
        if abs(gain - target) <= step {
            quickRecovery = false
        }
        return gain
    }
}

/// Volume and noise levels that glide (~25 ms one-pole) toward their
/// targets, so dragging the slider or toggling noise never steps or clicks.
public struct LevelSmoother: Sendable {
    public private(set) var volume: Float
    public private(set) var noise: Float

    public init(volume: Float, noise: Float) {
        self.volume = volume
        self.noise = noise
    }

    public static func coefficient(sampleRate: Double) -> Float {
        Float(1 - exp(-1 / (sampleRate * 0.025)))
    }

    @inline(__always)
    public mutating func advance(volume target: Float, noise noiseTarget: Float, coefficient: Float) {
        volume += (target - volume) * coefficient
        noise += (noiseTarget - noise) * coefficient
    }
}

/// Phase advance per sample for one frequency, as a rotation.
public struct Rotation: Sendable {
    public let cos: Double
    public let sin: Double

    public init(frequency: Double, sampleRate: Double) {
        let step = 2 * Double.pi * frequency / sampleRate
        cos = Foundation.cos(step)
        sin = Foundation.sin(step)
    }
}

/// Sine generator that rotates a unit phasor: one complex multiply per
/// sample instead of a sin() call, phase-continuous across buffers. Starts
/// at phase 0 (value 0) like a freshly reset phase accumulator.
public struct SineOscillator: Sendable {
    private var s: Double = 0 // sin(phase)
    private var c: Double = 1 // cos(phase)

    public mutating func reset() {
        s = 0
        c = 1
    }

    /// The current sample, then advance one step.
    @inline(__always)
    public mutating func next(_ rotation: Rotation) -> Double {
        let value = s
        let nextS = s * rotation.cos + c * rotation.sin
        c = c * rotation.cos - s * rotation.sin
        s = nextS
        return value
    }

    /// Pull the phasor back onto the unit circle (call once per buffer).
    public mutating func renormalize() {
        let magnitude = (s * s + c * c).squareRoot()
        guard magnitude > 0 else {
            reset()
            return
        }
        s /= magnitude
        c /= magnitude
    }
}

/// Soft ambient noise: the average of 16 random rows, one of which is
/// replaced per sample (a cheap low-pass "Voss" style generator), driven by
/// an xorshift PRNG. A plain value type: no allocation, no locks, no system
/// calls, so it is safe on the realtime audio thread.
public struct NoiseGenerator: Sendable {
    private var rows = SIMD16<Float>(repeating: 0)
    private var sum: Float = 0
    private var state: UInt32 = 0x9E37_79B9

    /// Next sample in roughly [-1, 1] (mostly far smaller, being an average).
    @inline(__always)
    public mutating func next() -> Float {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        let row = Int(state & 15)
        let value = Float(state >> 8) / Float(1 << 23) - 1
        sum += value - rows[row]
        rows[row] = value
        return sum / 16
    }

    /// Recompute the running sum exactly (call once per buffer) so float
    /// rounding can't build up a DC offset over hours of playback.
    public mutating func resync() {
        sum = rows.sum()
    }
}
