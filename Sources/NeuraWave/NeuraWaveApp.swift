import AppKit
import SwiftUI

@main
struct NeuraWaveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // A single-instance Window (not a WindowGroup): "Show Window" can
        // always bring back the one main window, even after it was closed.
        Window(MainWindow.title, id: MainWindow.id) {
            ContentView()
                .modifier(OpenWindowBridge())
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var autoTestRunner: AutoTestRunner?
    private var launchedAtLogin = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        launchedAtLogin = LoginItem.isHandlingLoginLaunch()
        // Before any window reads settings. Self-tests never touch them.
        if AutoTestOptions(arguments: ProcessInfo.processInfo.arguments) == nil {
            SettingsStore.standard.migrateVolumeCurveIfNeeded()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The launch ('oapp') event is normally being handled during this
        // callback; check here as well as in willFinish to be safe.
        launchedAtLogin = launchedAtLogin || LoginItem.isHandlingLoginLaunch()
        let arguments = ProcessInfo.processInfo.arguments
        let autoTest = AutoTestOptions(arguments: arguments)

        // Login launches, and self-tests that don't need the window, run
        // without a window, Dock icon or focus stealing; self-tests never
        // take focus, since they run while you're working.
        if let autoTest {
            NSApp.setActivationPolicy(autoTest.showsWindow ? .regular : .accessory)
            if !autoTest.showsWindow { hideWindowAfterLaunch() }
        } else if launchedAtLogin {
            NSApp.setActivationPolicy(.accessory)
            hideWindowAfterLaunch()
        } else {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        menuBar = MenuBarController(session: .shared, showWindow: MainWindow.show)

        if let index = arguments.firstIndex(of: "--screenshot"), index + 1 < arguments.count {
            DeveloperTools.renderScreenshot(to: arguments[index + 1])
        }

        if let autoTest {
            // Started here rather than in the view's onAppear so it runs even
            // when no window is ever presented (e.g. display asleep).
            let runner = AutoTestRunner(session: .shared, options: autoTest)
            autoTestRunner = runner
            runner.start()
            if autoTest.windowCheck {
                DeveloperTools.runWindowCheck()
            }
        } else {
            // Default-on launch at login: starts quietly in the menu bar and
            // never plays sound until you press Start.
            LoginItem.applyDefaultIfNeeded()
            dropToMenuBarWhenWindowCloses()
        }
    }

    /// SwiftUI may present the window a beat after launch, so hide it on the
    /// next turn and once more shortly after.
    private func hideWindowAfterLaunch() {
        DispatchQueue.main.async { MainWindow.hide() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { MainWindow.hide() }
    }

    /// Closing the window drops the app to menu-bar-only (no Dock icon); it
    /// keeps running until an explicit Quit / ⌘Q.
    private func dropToMenuBarWhenWindowCloses() {
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { _ in
            // Re-check once the close has completed. Any window closing
            // triggers this; only the main window's state matters.
            DispatchQueue.main.async {
                if !MainWindow.isOpen {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }

    /// Quitting mid-session (⌘Q, menu bar Quit) would cut the tone off
    /// mid-cycle — an audible click. Glide the level to zero first.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let session = SessionController.shared
        guard session.audio.isAudible else { return .terminateNow }
        session.audio.update(volume: 0, noiseEnabled: false)
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
        if !flag { MainWindow.show() }
        return true
    }
}

/// Hands SwiftUI's openWindow action to MainWindow once the view exists.
private struct OpenWindowBridge: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onAppear {
            MainWindow.openAction = { openWindow(id: MainWindow.id) }
        }
    }
}
