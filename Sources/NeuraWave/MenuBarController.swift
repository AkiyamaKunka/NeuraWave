import AppKit
import Combine
import ServiceManagement

/// Menu bar item so a session keeps running (and can be controlled) after the
/// window is closed. The window is optional; the sound is not.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let session: SessionController
    private let showWindow: () -> Void
    private var cancellables = Set<AnyCancellable>()

    init(session: SessionController, showWindow: @escaping () -> Void) {
        self.session = session
        self.showWindow = showWindow
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.button?.image = Self.icon(isPlaying: session.isPlaying, paused: session.isPaused)
        statusItem.button?.toolTip = "NeuraWave"
        statusItem.button?.setAccessibilityLabel("NeuraWave")

        // Keep the menu bar icon in sync with every start/stop/pause/resume,
        // including state changes initiated from the main window.
        session.$isPlaying.combineLatest(session.$isPaused, session.$sessionTitle)
            .sink { [weak self] playing, paused, title in
                guard let self else { return }
                self.statusItem.button?.image = Self.icon(isPlaying: playing, paused: paused)
                // Hovering the icon tells you what is playing.
                self.statusItem.button?.toolTip = playing
                    ? "NeuraWave — \(title)\(paused ? " (paused)" : "")"
                    : "NeuraWave"
            }
            .store(in: &cancellables)

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private static func icon(isPlaying: Bool, paused: Bool = false) -> NSImage? {
        let symbol = paused ? "pause.circle.fill" : (isPlaying ? "waveform.circle.fill" : "waveform.circle")
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
            title: session.isPlaying
                ? (session.isPaused ? "Paused — tap to resume" : "Playing — tap to pause")
                : "Tap to start",
            action: #selector(togglePlayback),
            keyEquivalent: ""
        )
        status.target = self
        menu.addItem(status)

        if session.isPlaying, session.programTitle == nil {
            let now = NSMenuItem(title: session.displayTitle, action: nil, keyEquivalent: "")
            now.isEnabled = false
            menu.addItem(now)
        }

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

        if session.isPlaying {
            let stop = NSMenuItem(title: "Stop", action: #selector(stopPlayback), keyEquivalent: "")
            stop.target = self
            menu.addItem(stop)
        }

        // Presets straight from the menu bar (the window is optional).
        let presets = NSMenuItem(title: "Presets", action: nil, keyEquivalent: "")
        let presetMenu = NSMenu()
        for preset in BrainwavePreset.all {
            let item = NSMenuItem(
                title: "\(preset.name) · \(preset.band)",
                action: #selector(playPreset(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = preset.id
            item.state = session.isPlaying && session.currentPreset.id == preset.id ? .on : .off
            // A running program owns the preset sequence.
            item.isEnabled = !session.isRunningProgram
            presetMenu.addItem(item)
        }
        presetMenu.autoenablesItems = false
        presets.submenu = presetMenu
        menu.addItem(presets)

        menu.addItem(.separator())
        let show = NSMenuItem(title: "Show Window", action: #selector(openWindow), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        switch SMAppService.mainApp.status {
        case .enabled:
            login.state = .on
        case .requiresApproval:
            login.state = .mixed
            login.title = "Launch at Login (approve in System Settings)"
        default:
            login.state = .off
        }
        login.target = self
        menu.addItem(login)
        let quit = NSMenuItem(title: "Quit NeuraWave", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func togglePlayback() {
        session.togglePlayPause()
    }

    @objc private func playPreset(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let preset = BrainwavePreset.all.first(where: { $0.id == id }) else { return }
        session.playPreset(preset)
    }

    @objc private func stopPlayback() {
        session.stop()
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
            // macOS can require the user to approve login items; without
            // this the toggle just silently stays off.
            if service.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        }
    }

    @objc private func quitApp() {
        // AppDelegate fades out and stops the session before terminating.
        NSApp.terminate(nil)
    }

    private static func format(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
