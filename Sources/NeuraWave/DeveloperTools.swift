import AppKit
import NeuraWaveCore
import SwiftUI

/// Command-line helpers for docs and self-tests (not used in normal runs).
@MainActor
enum DeveloperTools {
    /// `--screenshot <path>`: renders the real UI offscreen at 2x scale for a
    /// crisp README image, then exits.
    static func renderScreenshot(to path: String) -> Never {
        // NSHostingView snapshot is the reliable path (ImageRenderer produced
        // a partially-drawn image under some system appearances).
        let root = NSHostingView(rootView: ContentView().frame(width: 500))
        root.frame = NSRect(x: 0, y: 0, width: 500, height: 700)
        root.layoutSubtreeIfNeeded()
        guard let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds) else {
            fail("screenshot render failed")
        }
        root.cacheDisplay(in: root.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            fail("screenshot png encode failed")
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
        } catch {
            fail("screenshot write failed")
        }
        print("screenshot written to " + path)
        exit(0)
    }

    /// `--autotest-window-check`: close the main window, then "Show Window"
    /// must bring it back. Needs a logged-in, awake display; otherwise no
    /// window is ever shown and the check reports itself skipped.
    static func runWindowCheck() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let visible = MainWindow.windows.filter(\.isVisible)
            guard !visible.isEmpty else {
                print("WINDOW_CHECK skipped (no window presented; display asleep or locked?)")
                return
            }
            visible.forEach { $0.performClose(nil) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                MainWindow.show()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                print("WINDOW_CHECK \(MainWindow.windows.contains(where: \.isVisible) ? "ok" : "FAIL")")
            }
        }
    }

    private static func fail(_ message: String) -> Never {
        fputs(message + "\n", stderr)
        exit(1)
    }
}
