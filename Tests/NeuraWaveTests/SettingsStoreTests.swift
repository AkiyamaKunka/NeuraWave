import XCTest
@testable import NeuraWave

final class SettingsStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        suiteName = "NeuraWaveTests.SettingsStore"
        defaults = UserDefaults(suiteName: suiteName)
        // Fixed name (no plist per run); clear leftovers from a killed run.
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testFreshInstallDefaults() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.preset.id, "focus")
        XCTAssertEqual(store.style, .binaural)
        XCTAssertEqual(store.volume, VolumeLevel.defaultValue)
        XCTAssertFalse(store.noise)
        XCTAssertNil(store.minutes)
        XCTAssertNil(store.program)
        XCTAssertFalse(store.didApplyDefaultLoginItem)
    }

    func testRoundTrip() {
        let store = SettingsStore(defaults: defaults)
        store.preset = BrainwavePreset.byId("meditation")
        store.style = .isochronic
        store.volume = 0.7
        store.noise = true
        store.minutes = 45
        store.program = FocusProgram.all[1]
        store.didApplyDefaultLoginItem = true

        let reread = SettingsStore(defaults: defaults)
        XCTAssertEqual(reread.preset.id, "meditation")
        XCTAssertEqual(reread.style, .isochronic)
        XCTAssertEqual(reread.volume, 0.7)
        XCTAssertTrue(reread.noise)
        XCTAssertEqual(reread.minutes, 45)
        XCTAssertEqual(reread.program?.id, FocusProgram.all[1].id)
        XCTAssertTrue(reread.didApplyDefaultLoginItem)

        reread.minutes = nil
        reread.program = nil
        XCTAssertNil(store.minutes)
        XCTAssertNil(store.program)
    }

    /// Values written by earlier versions (same keys) and junk both load safely.
    func testLegacyAndCorruptValues() {
        defaults.set("relax", forKey: "preset")
        defaults.set("Isochronic", forKey: "style")
        defaults.set(0, forKey: "minutes")
        defaults.set("", forKey: "program")
        var store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.preset.id, "relax")
        XCTAssertEqual(store.style, .isochronic)
        XCTAssertNil(store.minutes)
        XCTAssertNil(store.program)

        defaults.set("gone-preset", forKey: "preset")
        defaults.set("Stereo", forKey: "style")
        defaults.set(42.0, forKey: "volume")
        store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.preset.id, "focus")
        XCTAssertEqual(store.style, .binaural)
        XCTAssertEqual(store.volume, 1)
    }

    func testVolumeCurveMigrationKeepsTheSameLoudnessOnce() {
        defaults.set(0.25, forKey: "volume") // old linear amplitude
        let store = SettingsStore(defaults: defaults)
        store.migrateVolumeCurveIfNeeded()
        XCTAssertEqual(store.volume, 0.5, accuracy: 1e-9, "√0.25: same amplitude on the new curve")
        XCTAssertEqual(Double(SessionController.amplitude(store.volume)), 0.25, accuracy: 1e-6)
        store.migrateVolumeCurveIfNeeded() // second launch: untouched
        XCTAssertEqual(store.volume, 0.5, accuracy: 1e-9)
    }

    func testDefaultSliderPositionGivesTheDefaultLoudness() {
        // 0.385 output: the softer default from 1.5.0 (1.4.0 used 0.55).
        XCTAssertEqual(Double(SessionController.amplitude(VolumeLevel.defaultValue)), 0.385, accuracy: 0.002)
    }

    func testDetectsSettingsFromAnEarlierVersion() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertFalse(store.hasEarlierVersionSettings, "fresh install")
        defaults.set("relax", forKey: "preset")
        XCTAssertTrue(store.hasEarlierVersionSettings)
    }
}
