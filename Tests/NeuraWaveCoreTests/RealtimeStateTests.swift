import AVFoundation
@testable import NeuraWaveCore
import XCTest

/// Drives the realtime render path directly, the way the audio thread does.
final class RealtimeStateTests: XCTestCase {
    private let sampleRate = 48_000.0
    private let chunk: AVAudioFrameCount = 512

    private func makeBuffer() -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk)!
        buffer.frameLength = chunk
        return buffer
    }

    /// Renders `seconds` of audio; returns the peak absolute sample and
    /// whether any sample was non-finite or outside [-1, 1].
    @discardableResult
    private func render(_ state: RealtimeState, seconds: Double, into buffer: AVAudioPCMBuffer? = nil) -> (peak: Float, bad: Bool) {
        let buffer = buffer ?? makeBuffer()
        let chunks = Int((seconds * sampleRate) / Double(chunk))
        var peak: Float = 0
        var bad = false
        for _ in 0..<max(1, chunks) {
            state.render(
                buffers: UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList),
                frameCount: Int(chunk),
                sampleRate: sampleRate
            )
            for channel in 0..<2 {
                let samples = buffer.floatChannelData![channel]
                for i in 0..<Int(chunk) {
                    let value = samples[i]
                    if !value.isFinite || abs(value) > 1 { bad = true }
                    peak = max(peak, abs(value))
                }
            }
        }
        return (peak, bad)
    }

    private func preset(_ id: String) -> BrainwavePreset {
        BrainwavePreset.all.first { $0.id == id }!
    }

    func testStartFadesInGentlyOverAboutTwoSeconds() {
        let state = RealtimeState()
        state.configure(preset: preset("relax"), style: .binaural, volume: 0.5, noiseEnabled: false)
        state.setRunning(true)

        render(state, seconds: 0.5)
        let early = state.diagnostics().gain
        XCTAssertGreaterThan(early, 0.15, "fade-in should be under way")
        XCTAssertLessThan(early, 0.4, "start must use the slow fade, not the quick switch ramp")

        render(state, seconds: 2)
        XCTAssertEqual(state.diagnostics().gain, 1, accuracy: 0.001)
    }

    func testLiveSwitchDipsAndRecoversQuickly() {
        let state = RealtimeState()
        state.configure(preset: preset("relax"), style: .binaural, volume: 0.5, noiseEnabled: false)
        state.setRunning(true)
        render(state, seconds: 2.5)

        state.configure(preset: preset("focus"), style: .isochronic, volume: 0.5, noiseEnabled: true)
        render(state, seconds: 0.3)
        let diagnostics = state.diagnostics()
        XCTAssertEqual(diagnostics.switches, 2)
        XCTAssertEqual(diagnostics.gain, 1, accuracy: 0.001, "quick ramp back up after the dip")
    }

    func testEveryPresetAndStyleRendersFiniteBoundedAudio() {
        for preset in BrainwavePreset.all {
            for style in ToneStyle.allCases {
                for noise in [false, true] {
                    let state = RealtimeState()
                    state.configure(preset: preset, style: style, volume: 1, noiseEnabled: noise)
                    state.setRunning(true)
                    let result = render(state, seconds: 2.2)
                    XCTAssertFalse(result.bad, "\(preset.id)/\(style)/noise=\(noise) produced NaN or clipping")
                    XCTAssertGreaterThan(result.peak, 0.1, "\(preset.id)/\(style) is silent")
                    XCTAssertEqual(state.diagnostics().clips, 0)
                }
            }
        }
    }

    func testPauseFadesToSilence() {
        let state = RealtimeState()
        state.configure(preset: preset("meditation"), style: .binaural, volume: 0.5, noiseEnabled: true)
        state.setRunning(true)
        render(state, seconds: 2.5)
        state.setRunning(false)
        render(state, seconds: 2.5)
        XCTAssertEqual(state.diagnostics().gain, 0, accuracy: 0.0001)
        XCTAssertEqual(render(state, seconds: 0.1).peak, 0, accuracy: 0.0001)
    }

    /// Regression test for the lost-update race: configuration requests made
    /// while the audio thread is mid-render must never vanish. Every request
    /// is either applied or explicitly superseded by a newer one.
    func testNoConfigurationRequestIsLostWhileRendering() {
        let state = RealtimeState()
        state.configure(preset: preset("relax"), style: .binaural, volume: 0.3, noiseEnabled: false)
        state.setRunning(true)

        let stop = ManagedAtomicFlag()
        let audioThread = Thread { [self] in
            let buffer = makeBuffer()
            while !stop.isSet {
                render(state, seconds: 0, into: buffer)
            }
        }
        audioThread.qualityOfService = .userInteractive
        audioThread.start()

        let presets = BrainwavePreset.all
        for i in 0..<300 {
            state.configure(
                preset: presets[i % presets.count],
                style: i.isMultiple(of: 2) ? .binaural : .isochronic,
                volume: 0.3,
                noiseEnabled: i.isMultiple(of: 3)
            )
            state.update(volume: Float(i % 10) / 10, noiseEnabled: i.isMultiple(of: 2))
            usleep(UInt32.random(in: 200...4_000))
        }
        // Let the final request finish its dip before stopping the thread.
        usleep(300_000)
        stop.set()
        while !audioThread.isFinished { usleep(1_000) }

        let (requested, coalesced) = state.requests()
        let applied = state.diagnostics().switches
        XCTAssertEqual(requested, 301)
        XCTAssertEqual(requested, applied + coalesced, "requested=\(requested) applied=\(applied) coalesced=\(coalesced)")
        // How many get superseded depends on machine load; the invariant
        // above is what matters. This only rules out a degenerate run.
        XCTAssertGreaterThan(applied, 20, "the render loop should apply plenty of requests")
    }
}

/// Minimal thread-safe flag for the render-loop test.
private final class ManagedAtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}
