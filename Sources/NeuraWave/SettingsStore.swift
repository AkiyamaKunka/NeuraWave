import Foundation

/// Typed access to everything NeuraWave remembers between launches. The
/// window writes each choice as you make it; the menu bar, AirPods and the
/// next launch read the same values, so they always agree.
///
/// Keys are unchanged from earlier versions, so existing settings carry over.
/// Invalid or out-of-range stored values fall back to sensible defaults.
struct SettingsStore {
    private enum Key {
        static let preset = "preset"
        static let style = "style"
        static let volume = "volume"
        static let noise = "noise"
        static let minutes = "minutes"
        static let program = "program"
        static let didApplyDefaultLoginItem = "didApplyDefaultLoginItem"
    }

    static var standard: SettingsStore { SettingsStore(defaults: .standard) }

    static let defaultPresetID = "focus"

    let defaults: UserDefaults

    var preset: BrainwavePreset {
        get {
            let id = defaults.string(forKey: Key.preset)
            return BrainwavePreset.all.first { $0.id == id } ?? BrainwavePreset.byId(Self.defaultPresetID)
        }
        nonmutating set { defaults.set(newValue.id, forKey: Key.preset) }
    }

    var style: ToneStyle {
        get { ToneStyle(rawValue: defaults.string(forKey: Key.style) ?? "") ?? .binaural }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.style) }
    }

    var volume: Double {
        get { VolumeLevel.sanitized(defaults.object(forKey: Key.volume) as? Double) }
        nonmutating set { defaults.set(newValue, forKey: Key.volume) }
    }

    var noise: Bool {
        get { defaults.bool(forKey: Key.noise) }
        nonmutating set { defaults.set(newValue, forKey: Key.noise) }
    }

    /// Sleep timer in minutes; nil = no timer.
    var minutes: Int? {
        get {
            let value = defaults.integer(forKey: Key.minutes)
            return value > 0 ? value : nil
        }
        nonmutating set { defaults.set(newValue ?? 0, forKey: Key.minutes) }
    }

    /// The focus program picked in the window; nil = play a single preset.
    var program: FocusProgram? {
        get {
            let id = defaults.string(forKey: Key.program)
            return FocusProgram.all.first { $0.id == id }
        }
        nonmutating set { defaults.set(newValue?.id ?? "", forKey: Key.program) }
    }

    var didApplyDefaultLoginItem: Bool {
        get { defaults.bool(forKey: Key.didApplyDefaultLoginItem) }
        nonmutating set { defaults.set(newValue, forKey: Key.didApplyDefaultLoginItem) }
    }
}
