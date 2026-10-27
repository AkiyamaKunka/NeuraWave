import Foundation

/// iPhone-only settings. Everything shared with the Mac (preset, style,
/// volume, noise, timer, program) lives in NeuraWaveCore's SettingsStore.
enum AppSettings {
    static let mixWithOthersKey = "mixWithOthers"

    static var mixWithOthers: Bool {
        UserDefaults.standard.bool(forKey: mixWithOthersKey)
    }
}
