import AppKit
import ServiceManagement
import SwiftUI

@main
struct NeuraWaveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("NeuraWave") {
            ContentView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        menuBar = MenuBarController(session: SessionController.shared, showWindow: { Self.showWindow() })

        let arguments = ProcessInfo.processInfo.arguments
        let isAutotest = arguments.contains("--autotest")

        if !isAutotest {
            // Default-on launch-at-login: starts quietly in the menu bar,
            // never plays sound until the user presses Start.
            Self.registerLoginItemIfNeeded()

            // Closing the window drops the app to menu-bar-only (no Dock
            // icon); it keeps running until an explicit Quit / Cmd+Q.
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: nil,
                queue: .main
            ) { note in
                guard let window = note.object as? NSWindow, window.title == "NeuraWave" else { return }
                DispatchQueue.main.async {
                    if !NSApp.windows.contains(where: { $0.title == "NeuraWave" && $0.isVisible }) {
                        NSApp.setActivationPolicy(.accessory)
                    }
                }
            }
        }

        // Self-test mode starts here rather than in the view's onAppear so it
        // runs even when no window is ever presented (e.g. display asleep).
        if isAutotest {
            let total = Self.intArgument(arguments, name: "--autotest-seconds", fallback: 1800)
            let cycle = Self.intArgument(arguments, name: "--autotest-cycle", fallback: 30)
            let timerMinutes = Self.intArgument(arguments, name: "--autotest-timer-minutes", fallback: 0)
            let stopAt = Self.intArgument(arguments, name: "--autotest-stop-at", fallback: 0)
            let volume = Self.doubleArgument(arguments, name: "--autotest-volume", fallback: 0.08)
            let programSeconds = Self.intArgument(arguments, name: "--autotest-program-seconds", fallback: 0)
            SessionController.shared.runAutoTest(
                totalSeconds: total,
                cycleSeconds: cycle,
                timerMinutes: timerMinutes > 0 ? timerMinutes : nil,
                stopAtSeconds: stopAt,
                volume: volume,
                programSeconds: programSeconds
            )
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Closing the window must not stop a running session: keep playing and
        // stay controllable from the menu bar (or the dock icon).
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { Self.showWindow() }
        return true
    }

    static func showWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.title == "NeuraWave" {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }

    static func registerLoginItemIfNeeded() {
        let service = SMAppService.mainApp
        guard service.status != .enabled else { return }
        try? service.register()
    }

    private static func intArgument(_ arguments: [String], name: String, fallback: Int) -> Int {
        guard let raw = argumentValue(arguments, name: name) else { return fallback }
        return Int(raw) ?? fallback
    }

    private static func doubleArgument(_ arguments: [String], name: String, fallback: Double) -> Double {
        guard let raw = argumentValue(arguments, name: name) else { return fallback }
        return Double(raw) ?? fallback
    }

    private static func argumentValue(_ arguments: [String], name: String) -> String? {
        if let equalsForm = arguments.first(where: { $0.hasPrefix(name + "=") }) {
            return String(equalsForm.dropFirst(name.count + 1))
        }
        if let index = arguments.firstIndex(of: name), index + 1 < arguments.count {
            return arguments[index + 1]
        }
        return nil
    }
}
