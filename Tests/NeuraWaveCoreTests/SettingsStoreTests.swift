@testable import NeuraWaveCore
import XCTest

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

    func testDetectsSettingsFromAnEarlierVersion() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertFalse(store.hasEarlierVersionSettings, "fresh install")
        defaults.set("relax", forKey: "preset")
        XCTAssertTrue(store.hasEarlierVersionSettings)
    }

    func testUpdatersWhoNeverMovedTheSliderKeepTheirLevel() {
        defaults.set("relax", forKey: "preset") // saved by an earlier version, no volume
        let store = SettingsStore(defaults: defaults)
        store.keepEarlierDefaultVolumeIfNeeded()
        XCTAssertEqual(store.volume, SettingsStore.earlierDefaultVolume)
        store.volume = 0.3
        store.keepEarlierDefaultVolumeIfNeeded() // only ever once
        XCTAssertEqual(store.volume, 0.3)
    }

    func testFreshInstallsGetTheNewDefault() {
        let store = SettingsStore(defaults: defaults)
        store.keepEarlierDefaultVolumeIfNeeded()
        XCTAssertEqual(store.volume, VolumeLevel.defaultValue)
        store.preset = BrainwavePreset.byId("relax") // later launches never apply it
        store.keepEarlierDefaultVolumeIfNeeded()
        XCTAssertEqual(store.volume, VolumeLevel.defaultValue)
    }
}
