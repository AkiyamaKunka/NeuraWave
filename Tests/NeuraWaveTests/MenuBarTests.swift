import AppKit
import XCTest
@testable import NeuraWave

@MainActor
final class MenuBarTests: XCTestCase {
    func testIdleMenu() {
        let session = SessionController(audio: FakeAudio(), nowPlaying: FakeNowPlaying())
        let controller = MenuBarController(session: session, showWindow: {})
        let menu = NSMenu()
        controller.menuNeedsUpdate(menu)
        let titles = menu.items.filter { !$0.isSeparatorItem }.map(\.title)
        XCTAssertEqual(titles.first, "NeuraWave")
        XCTAssertTrue(titles.contains("Start"))
        XCTAssertFalse(titles.contains("Stop"), "nothing to stop while idle")
        XCTAssertTrue(titles.contains("Show Window"))
        XCTAssertTrue(titles.contains("Quit NeuraWave"))

        let presets = try? XCTUnwrap(menu.items.first { $0.title == "Presets" }?.submenu)
        XCTAssertEqual(presets?.items.count, BrainwavePreset.all.count)
        XCTAssertTrue(presets?.items.allSatisfy { $0.isEnabled && $0.state == .off } ?? false)
    }

    func testPlayingMenuAndLiveCountdown() {
        var clock = Date(timeIntervalSinceReferenceDate: 0)
        let suite = "NeuraWaveTests.MenuBar"
        let settings = SettingsStore(defaults: UserDefaults(suiteName: suite)!)
        defer { settings.defaults.removePersistentDomain(forName: suite) }
        let session = SessionController(audio: FakeAudio(), nowPlaying: FakeNowPlaying(), settings: settings) { clock }
        let controller = MenuBarController(session: session, showWindow: {})
        session.start(preset: BrainwavePreset.byId("relax"), style: .binaural, volume: 0.4, withNoise: false, minutes: 15)

        let menu = NSMenu()
        controller.menuNeedsUpdate(menu)
        let titles = menu.items.map(\.title)
        XCTAssertTrue(titles.contains("Pause"))
        XCTAssertTrue(titles.contains("Relax"))
        XCTAssertTrue(titles.contains("Remaining 15:00"))
        XCTAssertTrue(titles.contains("Stop"))
        let relax = menu.items.first { $0.title == "Presets" }?.submenu?.items.first { $0.title.hasPrefix("Relax") }
        XCTAssertEqual(relax?.state, .on)

        // While the menu stays open, the countdown keeps ticking.
        clock = clock.addingTimeInterval(65)
        session.tick()
        XCTAssertTrue(menu.items.map(\.title).contains("Remaining 13:55"))

        controller.menuDidClose(menu)
        session.stop()
    }
}
