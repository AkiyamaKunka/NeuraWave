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

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild(menu)
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(info("NeuraWave"))
        menu.addItem(.separator())
        addSessionItems(to: menu)
        menu.addItem(presetsItem())
        menu.addItem(.separator())
        menu.addItem(action("Show Window", #selector(openWindow)))
        menu.addItem(loginItem())
        menu.addItem(action("Quit NeuraWave", #selector(quitApp), key: "q"))
    }

    /// Start / Pause / Resume, what is playing, the countdown, and Stop.
    private func addSessionItems(to menu: NSMenu) {
        let toggleTitle = !session.isPlaying ? "Start" : (session.isPaused ? "Resume" : "Pause")
        menu.addItem(action(toggleTitle, #selector(togglePlayback)))
        guard session.isPlaying else { return }
        menu.addItem(info(session.programTitle ?? session.sessionTitle))
        if let remaining = session.remainingSeconds {
            menu.addItem(info("Remaining \(TimeFormat.clock(remaining))"))
        }
        menu.addItem(action("Stop", #selector(stopPlayback)))
    }

    /// Presets straight from the menu bar (the window is optional).
    private func presetsItem() -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for preset in BrainwavePreset.all {
            let item = action("\(preset.name) · \(preset.band)", #selector(playPreset(_:)))
            item.representedObject = preset.id
            item.state = session.isPlaying && session.currentPreset.id == preset.id ? .on : .off
            // A running program owns the preset sequence.
            item.isEnabled = !session.isRunningProgram
            submenu.addItem(item)
        }
        let presets = NSMenuItem(title: "Presets", action: nil, keyEquivalent: "")
        presets.submenu = submenu
        return presets
    }

    private func loginItem() -> NSMenuItem {
        let item = action("Launch at Login", #selector(toggleLoginItem))
        switch SMAppService.mainApp.status {
        case .enabled:
            item.state = .on
        case .requiresApproval:
            item.state = .mixed
            item.title = "Launch at Login (approve in System Settings)"
        default:
            item.state = .off
        }
        return item
    }

    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    /// A greyed-out, informational line.
    private func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
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
}
