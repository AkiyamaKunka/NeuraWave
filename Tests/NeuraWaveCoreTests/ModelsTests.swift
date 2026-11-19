@testable import NeuraWaveCore
import XCTest

final class ModelsTests: XCTestCase {
    private func program(_ id: String) -> FocusProgram {
        FocusProgram.all.first { $0.id == id }!
    }

    func testProgramLengthsMatchTheREADME() {
        XCTAssertEqual(program("study").totalSeconds, 40 * 60)
        XCTAssertEqual(program("coding").totalSeconds, 43 * 60)
        XCTAssertEqual(program("rest").totalSeconds, 30 * 60)
    }

    func testStepIndexFollowsTheSchedule() {
        let coding = program("coding") // 8 min → 30 min → 5 min
        XCTAssertEqual(coding.stepIndex(at: -5), 0)
        XCTAssertEqual(coding.stepIndex(at: 0), 0)
        XCTAssertEqual(coding.stepIndex(at: 8 * 60 - 0.001), 0)
        XCTAssertEqual(coding.stepIndex(at: 8 * 60), 1)
        XCTAssertEqual(coding.stepIndex(at: 38 * 60 - 0.001), 1)
        XCTAssertEqual(coding.stepIndex(at: 38 * 60), 2)
        XCTAssertEqual(coding.stepIndex(at: 43 * 60), 2, "past the end stays on the last step")
        XCTAssertEqual(coding.stepIndex(at: 10_000), 2)
    }

    func testPresetIdsAreUniqueAndLookupNeverCrashes() {
        let ids = BrainwavePreset.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(BrainwavePreset.byId("focus").name, "Deep Focus")
        XCTAssertEqual(BrainwavePreset.byId("no-such-preset").id, "unknown")
    }

    func testBeatsSitInsideTheirAdvertisedBands() {
        let bands: [String: ClosedRange<Double>] = [
            "Delta": 0.5...4, "Theta": 4...8, "Alpha": 8...13,
            "SMR": 12...15, "Beta": 13...30, "Gamma": 30...100
        ]
        for preset in BrainwavePreset.all {
            let range = bands[preset.band]
            XCTAssertNotNil(range, "unknown band \(preset.band)")
            XCTAssertTrue(range?.contains(preset.beat) ?? false, "\(preset.name) \(preset.beat) Hz outside \(preset.band)")
            XCTAssertGreaterThan(preset.carrier, preset.beat * 2, "carrier must sit well above the beat")
        }
    }

    func testSavedVolumeIsSanitized() {
        XCTAssertEqual(VolumeLevel.sanitized(nil), VolumeLevel.defaultValue)
        XCTAssertEqual(VolumeLevel.sanitized(.nan), VolumeLevel.defaultValue)
        XCTAssertEqual(VolumeLevel.sanitized(5), 1)
        XCTAssertEqual(VolumeLevel.sanitized(-1), 0.05)
        XCTAssertEqual(VolumeLevel.sanitized(0.5), 0.5)
    }

    func testDisplayStrings() {
        XCTAssertEqual(BrainwavePreset.byId("deep-sleep").beatLabel, "2.5 Hz")
        XCTAssertEqual(BrainwavePreset.byId("peak").beatLabel, "40 Hz")
        XCTAssertEqual(FocusProgram.all.first { $0.id == "coding" }?.bandSummary, "Beta→Gamma→Alpha")
        XCTAssertEqual(TimeFormat.clock(0), "00:00")
        XCTAssertEqual(TimeFormat.clock(65), "01:05")
        XCTAssertEqual(TimeFormat.clock(90 * 60), "90:00")
        XCTAssertEqual(TimeFormat.clock(-3), "00:00")
    }
}
