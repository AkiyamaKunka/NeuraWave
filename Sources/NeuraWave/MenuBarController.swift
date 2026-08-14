import AppKit
import ServiceManagement

/// Menu bar item so a session keeps running (and can be controlled) after the
/// window is closed. The window is optional; the sound is not.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let session: SessionController
    private let showWindow: () -> Void

    init(session: SessionController, showWindow: @escaping () -> Void) {
        self.session = session
        self.showWindow = showWindow
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.button?.image = Self.icon(isPlaying: session.isPlaying)
        statusItem.button?.toolTip = "NeuraWave"
        statusItem.button?.setAccessibilityLabel("NeuraWave")

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private static func icon(isPlaying: Bool) -> NSImage? {
        let symbol = isPlaying ? "waveform.circle.fill" : "waveform.circle"
        return NSImage(systemSymbolName: symbol, accessibilityDescription: "NeuraWave")
    }

    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            rebuild(menu)
        }
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = NSMenuItem(title: "NeuraWave", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let status = NSMenuItem(
            title: session.isPlaying ? "Playing — tap to stop" : "Tap to start",
            action: #selector(togglePlayback),
            keyEquivalent: ""
        )
        status.target = self
        menu.addItem(status)

        if session.isPlaying, let remaining = session.remainingSeconds {
            let countdown = NSMenuItem(title: "Remaining \(Self.format(remaining))", action: nil, keyEquivalent: "")
            countdown.isEnabled = false
            menu.addItem(countdown)
        }

        if let title = session.programTitle {
            let prog = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            prog.isEnabled = false
            menu.addItem(prog)
        }

        menu.addItem(.separator())
        let show = NSMenuItem(title: "Show Window", action: #selector(openWindow), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        login.target = self
        menu.addItem(login)
        let quit = NSMenuItem(title: "Quit NeuraWave", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func togglePlayback() {
        if session.isPlaying {
            session.stop()
        } else {
            session.startLast()
        }
        statusItem.button?.image = Self.icon(isPlaying: session.isPlaying)
    }

    @objc private func openWindow() {
        showWindow()
    }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        if service.status == .enabled {
            try? service.unregister()
        } else {
            try? service.register()
        }
    }

    @objc private func quitApp() {
        session.stop()
        NSApp.terminate(nil)
    }

    private static func format(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
