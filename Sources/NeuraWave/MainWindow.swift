import AppKit
import NeuraWaveCore

/// The app's single main window.
@MainActor
enum MainWindow {
    static let id = "main"
    static let title = "NeuraWave"
    /// SwiftUI's openWindow action, captured from the view tree so AppKit
    /// code (menu bar, Dock reopen) can recreate a closed window.
    static var openAction: (() -> Void)?

    static var windows: [NSWindow] {
        NSApp.windows.filter { $0.title == title }
    }

    /// Visible or minimized (a minimized window keeps its Dock tile).
    static var isOpen: Bool {
        windows.contains { $0.isVisible || $0.isMiniaturized }
    }

    static func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = windows.first {
            window.makeKeyAndOrderFront(nil)
        } else {
            // The window was closed and released: ask SwiftUI for a new one.
            openAction?()
        }
    }

    /// orderOut (not close) keeps the window alive so show() can bring it
    /// straight back.
    static func hide() {
        windows.forEach { $0.orderOut(nil) }
    }
}
