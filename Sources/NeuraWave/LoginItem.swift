import AppKit
import ServiceManagement

/// Launch at Login, via SMAppService.
@MainActor
enum LoginItem {
    enum State {
        case on
        case off
        /// Registered, but macOS wants the user to approve it in System Settings.
        case needsApproval
    }

    static var state: State {
        switch SMAppService.mainApp.status {
        case .enabled: return .on
        case .requiresApproval: return .needsApproval
        default: return .off
        }
    }

    /// Menu bar toggle. Turning it on may need approval; then System Settings
    /// opens, because otherwise the toggle would just silently stay off.
    static func toggle() {
        let service = SMAppService.mainApp
        if service.status == .enabled {
            try? service.unregister()
        } else {
            try? service.register()
            if service.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        }
    }

    /// Default-on launch at login, applied once on first run. After that the
    /// menu bar toggle is the source of truth, so turning it off sticks.
    static func applyDefaultIfNeeded(settings: SettingsStore = .standard) {
        guard !settings.didApplyDefaultLoginItem else { return }
        let service = SMAppService.mainApp
        if service.status != .enabled {
            try? service.register()
        }
        // Only remember once it took (a first run from a translocated DMG
        // copy can fail); otherwise try again next launch.
        if service.status == .enabled || service.status == .requiresApproval {
            settings.didApplyDefaultLoginItem = true
        }
    }

    /// True when macOS opened the app as a login item (the launch Apple event
    /// carries keyAELaunchedAsLogInItem). Only meaningful while the launch
    /// event is being handled, i.e. during app launch.
    static func isHandlingLoginLaunch() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}

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
