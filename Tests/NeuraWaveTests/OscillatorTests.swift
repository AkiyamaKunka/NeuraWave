import XCTest
@testable import NeuraWave

final class OscillatorTests: XCTestCase {
    /// The phasor oscillator must track sin(2πft) closely over a long
    /// session (here 10 minutes at 48 kHz, renormalized per 512-sample
    /// buffer like the render loop does).
    func testTracksTheExactSineOverTenMinutes() {
        let sampleRate = 48_000.0
        for frequency in [174.0, 320.0, 40.0] {
            let rotation = Rotation(frequency: frequency, sampleRate: sampleRate)
            var oscillator = SineOscillator()
            var worst = 0.0
            let total = Int(sampleRate * 600)
            for n in 0..<total {
                let value = oscillator.next(rotation)
                // Spot-check (computing the reference every sample is what's slow).
                if n % 101 == 0 {
                    let expected = sin(2 * Double.pi * frequency * Double(n) / sampleRate)
                    worst = max(worst, abs(value - expected))
                }
                if n % 512 == 511 { oscillator.renormalize() }
            }
            // Far below what 32-bit float output can even represent.
            XCTAssertLessThan(worst, 1e-6, "\(frequency) Hz drifted by \(worst)")
        }
    }

    func testResetStartsAtPhaseZero() {
        let rotation = Rotation(frequency: 1000, sampleRate: 48_000)
        var oscillator = SineOscillator()
        for _ in 0..<1234 { _ = oscillator.next(rotation) }
        oscillator.reset()
        XCTAssertEqual(oscillator.next(rotation), 0)
        XCTAssertEqual(oscillator.next(rotation), sin(2 * Double.pi * 1000 / 48_000), accuracy: 1e-12)
    }
}
