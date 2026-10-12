import AppKit
import ServiceManagement
import SwiftUI

@main
struct NeuraWaveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // A single-instance Window (not a WindowGroup): "Show Window" can
        // always bring back the one main window, even after it was closed.
        Window("NeuraWave", id: AppDelegate.mainWindowID) {
            ContentView()
                .modifier(OpenWindowBridge())
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let mainWindowID = "main"
    /// SwiftUI's openWindow action, captured from the view tree so AppKit
    /// code (menu bar, Dock reopen) can recreate a closed window.
    static var openMainWindow: (() -> Void)?

    private var menuBar: MenuBarController?
    private var autoTestRunner: AutoTestRunner?
    private var launchedAtLogin = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        launchedAtLogin = Self.wasLaunchedAsLoginItem()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The launch ('oapp') event is normally being handled during this
        // callback; check here as well as in willFinish to be safe.
        launchedAtLogin = launchedAtLogin || Self.wasLaunchedAsLoginItem()
        let arguments = ProcessInfo.processInfo.arguments
        let autoTestOptions = AutoTestOptions(arguments: arguments)
        let isAutotest = autoTestOptions != nil
        let launchedAtLogin = !isAutotest && self.launchedAtLogin

        if launchedAtLogin {
            // Login launch: menu bar only, no window, no focus stealing.
            NSApp.setActivationPolicy(.accessory)
            // orderOut (not close) keeps the window alive so "Show Window"
            // can bring it straight back. SwiftUI may present it a beat
            // after launch, so hide on the next turn and once more after.
            let hide: @MainActor @Sendable () -> Void = {
                for window in NSApp.windows where window.title == "NeuraWave" {
                    window.orderOut(nil)
                }
            }
            DispatchQueue.main.async(execute: hide)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: hide)
        } else if isAutotest {
            // Self-tests run alongside whatever you are doing: show the
            // window (some probes need it) but never steal focus, so a
            // stray Space keypress can't pause the run.
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        menuBar = MenuBarController(session: SessionController.shared, showWindow: { Self.showWindow() })

        // Headless screenshot rendering for docs (--screenshot <path>):
        // renders the real UI at 2x scale for a crisp README image.
        if let idx = arguments.firstIndex(of: "--screenshot"), idx + 1 < arguments.count {
            Self.renderScreenshot(to: arguments[idx + 1])
        }

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
            ) { _ in
                // Any window closing re-checks whether the main window is
                // still visible (after the close has completed).
                DispatchQueue.main.async {
                    // A minimized main window still counts as open (keeps
                    // its Dock tile).
                    if !NSApp.windows.contains(where: { $0.title == "NeuraWave" && ($0.isVisible || $0.isMiniaturized) }) {
                        NSApp.setActivationPolicy(.accessory)
                    }
                }
            }
        }

        // Self-test mode starts here rather than in the view's onAppear so it
        // runs even when no window is ever presented (e.g. display asleep).
        if let options = autoTestOptions {
            let runner = AutoTestRunner(session: .shared, options: options)
            autoTestRunner = runner
            runner.start()
            if options.windowCheck {
                Self.runWindowCheck()
            }
        }
    }

    /// Autotest: close the main window, then "Show Window" must bring it back.
    /// Needs a logged-in, awake display; otherwise no window is ever shown.
    private static func runWindowCheck() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let mainWindows = NSApp.windows.filter { $0.title == "NeuraWave" && $0.isVisible }
            guard !mainWindows.isEmpty else {
                print("WINDOW_CHECK skipped (no window presented; display asleep or locked?)")
                return
            }
            mainWindows.forEach { $0.performClose(nil) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                showWindow()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                let visible = NSApp.windows.contains { $0.title == "NeuraWave" && $0.isVisible }
                print("WINDOW_CHECK \(visible ? "ok" : "FAIL")")
            }
        }
    }

    /// Quitting mid-session (⌘Q, menu bar Quit) would cut the tone off
    /// mid-cycle — an audible click. Glide the level to zero first.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let session = SessionController.shared
        guard session.engine.isAudible else { return .terminateNow }
        session.engine.update(volume: 0, noiseEnabled: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            session.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
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
        // The window was closed and released: ask SwiftUI for a new one.
        openMainWindow?()
    }

    /// Default-on launch-at-login, applied once on first run. After that the
    /// menu bar toggle is the source of truth, so turning it off sticks.
    static func registerLoginItemIfNeeded() {
        let defaults = UserDefaults.standard
        let key = "didApplyDefaultLoginItem"
        guard !defaults.bool(forKey: key) else { return }
        let service = SMAppService.mainApp
        if service.status != .enabled {
            try? service.register()
        }
        // Only remember once it took (a first run from a translocated DMG
        // copy can fail); otherwise try again next launch.
        if service.status == .enabled || service.status == .requiresApproval {
            defaults.set(true, forKey: key)
        }
    }

    /// True when macOS opened the app as a login item (the launch Apple event
    /// carries keyAELaunchedAsLogInItem).
    static func wasLaunchedAsLoginItem() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    static func renderScreenshot(to path: String) {
        // NSHostingView snapshot is the reliable path (ImageRenderer produced
        // a partially-drawn image under some system appearances).
        let root = NSHostingView(rootView: ContentView().frame(width: 500))
        root.frame = NSRect(x: 0, y: 0, width: 500, height: 700)
        root.layoutSubtreeIfNeeded()
        guard let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds) else {
            fputs("screenshot render failed\n", stderr)
            exit(1)
        }
        root.cacheDisplay(in: root.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            fputs("screenshot png encode failed\n", stderr)
            exit(1)
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("screenshot written to " + path)
        } catch {
            fputs("screenshot write failed\n", stderr)
            exit(1)
        }
        exit(0)
    }
}

/// Hands SwiftUI's openWindow action to AppDelegate once the view exists.
private struct OpenWindowBridge: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onAppear {
            AppDelegate.openMainWindow = { openWindow(id: AppDelegate.mainWindowID) }
        }
    }
}
