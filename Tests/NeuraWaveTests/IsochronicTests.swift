import XCTest
@testable import NeuraWave

final class IsochronicTests: XCTestCase {
    private let sampleRate = 48_000.0

    private func render(_ style: ToneStyle, beat: Double = 10, seconds: Double = 2) -> [Float] {
        var voice = Voice()
        voice.retune(to: ToneConfig(carrier: 240, beat: beat, style: style), sampleRate: sampleRate)
        return (0..<Int(sampleRate * seconds)).map { _ in voice.next().left }
    }

    private func rms(_ samples: [Float]) -> Float {
        (samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)).squareRoot()
    }

    /// Full-depth pulses: the tone really goes silent between beats.
    func testPulsesReachSilenceBetweenBeats() {
        let samples = render(.isochronic)
        // Peak level in each 1 ms window.
        let windows = stride(from: 0, to: samples.count - 48, by: 48).map { start in
            samples[start..<start + 48].map(abs).max() ?? 0
        }
        XCTAssertLessThan(windows.min() ?? 1, 0.02, "troughs are silent")
        XCTAssertGreaterThan(windows.max() ?? 0, 1.1, "crests are loudness-compensated")
    }

    /// Same average loudness as the original 45–100% pulses, so the change
    /// doesn't make Isochronic sound quieter.
    func testLoudnessMatchesTheOriginalPulses() {
        let expected: Float = (0.5 * 0.5634).squareRoot() // sine RMS × old envelope RMS
        XCTAssertEqual(rms(render(.isochronic)), expected, accuracy: expected * 0.01)
    }

    func testBinauralIsUnaffected() {
        XCTAssertEqual(rms(render(.binaural)), (0.5 as Float).squareRoot(), accuracy: 0.005)
    }

    func testSwellIsSmoothSoNoClicks() {
        // A click would show up as a sample-to-sample jump far above what a
        // 240 Hz tone at this level can produce (2π·240/48000 · 1.23 ≈ 0.04).
        let samples = render(.isochronic, beat: 40)
        let biggestStep = zip(samples, samples.dropFirst()).map { abs($1 - $0) }.max() ?? 0
        XCTAssertLessThan(biggestStep, 0.06) // ≈0.042 today; a click would be far larger
    }

    func testPrecomputedLoudnessMatchesTheFormula() {
        XCTAssertEqual(Voice.isochronicLoudness, Voice.loudnessFactor(depth: Voice.isochronicDepth), accuracy: 0.0005)
    }
}
