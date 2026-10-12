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
}
