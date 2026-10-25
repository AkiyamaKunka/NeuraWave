@testable import NeuraWaveCore
import XCTest

final class GainFaderTests: XCTestCase {
    private let rate = 48_000.0
    private lazy var rates = GainFader.Rates(sampleRate: rate)

    /// Samples until `condition` holds, advancing with the given inputs.
    private func samples(_ fader: inout GainFader, running: Bool, switching: Bool, until condition: (GainFader) -> Bool) -> Int {
        var count = 0
        while !condition(fader), count < Int(rate * 10) {
            _ = fader.advance(running: running, switching: switching, rates: rates)
            count += 1
        }
        return count
    }

    func testStartFadesInOverTwoSeconds() {
        var fader = GainFader()
        let n = samples(&fader, running: true, switching: false) { $0.gain >= 1 }
        XCTAssertEqual(Double(n) / rate, 2.0, accuracy: 0.01)
    }

    func testLiveSwitchDipsIn60msAndRecoversIn150ms() {
        var fader = GainFader()
        _ = samples(&fader, running: true, switching: false) { $0.gain >= 1 }

        let down = samples(&fader, running: true, switching: true) { $0.isSilent }
        XCTAssertEqual(Double(down) / rate, 0.06, accuracy: 0.002)

        fader.didSwitch()
        let up = samples(&fader, running: true, switching: false) { $0.gain >= 1 }
        XCTAssertEqual(Double(up) / rate, 0.15, accuracy: 0.002)

        // The quick recovery is one-shot: the next stop fades slowly again.
        let stop = samples(&fader, running: false, switching: false) { $0.isSilent }
        XCTAssertEqual(Double(stop) / rate, 2.0, accuracy: 0.01)
    }

    func testToneAppliedFromSilenceKeepsTheGentleFadeIn() {
        var fader = GainFader()
        // A request pending while already silent (session start): no dip.
        _ = fader.advance(running: true, switching: true, rates: rates)
        fader.didSwitch()
        let n = samples(&fader, running: true, switching: false) { $0.gain >= 1 }
        XCTAssertEqual(Double(n) / rate, 2.0, accuracy: 0.01)
    }

    func testPausedSwitchStaysSilent() {
        var fader = GainFader()
        for _ in 0..<1_000 {
            XCTAssertEqual(fader.advance(running: false, switching: true, rates: rates), 0)
        }
    }

    func testLevelsGlideInsteadOfStepping() {
        var levels = LevelSmoother(volume: 0.2, noise: 0)
        let k = LevelSmoother.coefficient(sampleRate: rate)
        levels.advance(volume: 1, noise: 1, coefficient: k)
        XCTAssertLessThan(levels.volume, 0.21, "no jump on the first sample")
        for _ in 0..<Int(rate * 0.2) { levels.advance(volume: 1, noise: 1, coefficient: k) }
        XCTAssertEqual(levels.volume, 1, accuracy: 0.001, "settles within ~0.2 s")
        XCTAssertEqual(levels.noise, 1, accuracy: 0.001)
    }
}
