import SwiftUI

struct BrainwavePreset: Identifiable, Hashable {
    let id: String
    let name: String
    let band: String
    let beat: Double
    let carrier: Double
    let detail: String
    let color: Color

    static let all: [BrainwavePreset] = [
        BrainwavePreset(
            id: "deep-sleep",
            name: "Deep Sleep",
            band: "Delta",
            beat: 2.5,
            carrier: 174,
            detail: "0.5-4 Hz · deep, restorative sleep",
            color: .indigo
        ),
        BrainwavePreset(
            id: "meditation",
            name: "Meditation",
            band: "Theta",
            beat: 6.0,
            carrier: 210,
            detail: "4-8 Hz · calm and inner awareness",
            color: .teal
        ),
        BrainwavePreset(
            id: "relax",
            name: "Relax",
            band: "Alpha",
            beat: 10.0,
            carrier: 240,
            detail: "8-13 Hz · unwind and ease stress",
            color: .green
        ),
        BrainwavePreset(
            id: "calm-focus",
            name: "Calm Focus",
            band: "SMR",
            beat: 14.0,
            carrier: 190,
            detail: "12-15 Hz · steady attention, low strain",
            color: .blue
        ),
        BrainwavePreset(
            id: "focus",
            name: "Deep Focus",
            band: "Beta",
            beat: 16.0,
            carrier: 220,
            detail: "16 Hz · active concentration & problem solving",
            color: .orange
        ),
        BrainwavePreset(
            id: "peak",
            name: "Peak Concentration",
            band: "Gamma",
            beat: 40.0,
            carrier: 280,
            detail: "40 Hz · peak processing — best in Isochronic",
            color: .pink
        )
    ]

    /// "2.5 Hz", "16 Hz".
    var beatLabel: String {
        let number = beat == beat.rounded() ? String(Int(beat)) : String(format: "%.1f", beat)
        return number + " Hz"
    }

    /// Non-fatal lookup: an id that no longer exists (corrupted defaults,
    /// hand-written argument) falls back to a neutral preset instead of
    /// crashing the app on a force-unwrap.
    static func byId(_ id: String) -> BrainwavePreset {
        all.first { $0.id == id } ?? BrainwavePreset(
            id: "unknown",
            name: "Unknown",
            band: "—",
            beat: 10,
            carrier: 240,
            detail: "Unrecognized preset",
            color: .gray
        )
    }
}

/// Volume range the UI offers; anything else in saved settings (a bad
/// value, a hand-edited plist) is pulled back into it.
enum VolumeLevel {
    static let range: ClosedRange<Double> = 0.05...1.0
    /// Slider position (squared to amplitude): ≈0.385 output, the default
    /// loudness on the linear slider just before this change.
    static let defaultValue = 0.62

    static func sanitized(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return defaultValue }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

/// A timed sequence of presets that auto-advances (click-free crossfade).
/// Step design follows the evidence in RESEARCH.md: settle-in phases before
/// demanding work (Garcia-Argibay 2019), alpha gating (Klimesch 2012),
/// gamma via isochronic-favoring steps (ASSR literature), theta only in rest.
struct FocusProgram: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    let steps: [ProgramStep]

    struct ProgramStep: Hashable {
        let preset: BrainwavePreset
        let seconds: TimeInterval
    }

    var totalSeconds: TimeInterval { steps.reduce(0) { $0 + $1.seconds } }

    /// "Alpha→Beta".
    var bandSummary: String { steps.map(\.preset.band).joined(separator: "→") }

    /// Index of the step playing `elapsed` seconds into the program (the last
    /// step once the schedule is over; negative time counts as the start).
    func stepIndex(at elapsed: TimeInterval) -> Int {
        var end: TimeInterval = 0
        for (index, step) in steps.enumerated() {
            end += step.seconds
            if elapsed < end {
                return index
            }
        }
        return max(0, steps.count - 1)
    }

    static let all: [FocusProgram] = [
        FocusProgram(
            id: "study",
            name: "Study Flow",
            detail: "Alpha settle → Beta focus · reading & learning",
            steps: [
                ProgramStep(preset: byId("relax"), seconds: 10 * 60),
                ProgramStep(preset: byId("focus"), seconds: 30 * 60)
            ]
        ),
        FocusProgram(
            id: "coding",
            name: "Coding Sprint",
            detail: "Beta warm-up → Gamma peak → Alpha cool-down",
            steps: [
                ProgramStep(preset: byId("focus"), seconds: 8 * 60),
                ProgramStep(preset: byId("peak"), seconds: 30 * 60),
                ProgramStep(preset: byId("relax"), seconds: 5 * 60)
            ]
        ),
        FocusProgram(
            id: "rest",
            name: "Mental Rest",
            detail: "Alpha → Theta → Alpha · unwind (may cause drowsiness)",
            steps: [
                ProgramStep(preset: byId("relax"), seconds: 6 * 60),
                ProgramStep(preset: byId("meditation"), seconds: 20 * 60),
                ProgramStep(preset: byId("relax"), seconds: 4 * 60)
            ]
        )
    ]

    private static func byId(_ id: String) -> BrainwavePreset {
        BrainwavePreset.all.first { $0.id == id }!
    }
}

enum TimeFormat {
    /// Countdown text: "05:00", "90:00" (minutes keep counting past 59).
    static func clock(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

enum ToneStyle: String, CaseIterable, Identifiable {
    case binaural = "Binaural"
    case isochronic = "Isochronic"

    var id: String { rawValue }

    var tip: String {
        switch self {
        case .binaural:
            return "Two tones, one per ear · headphones recommended"
        case .isochronic:
            return "Pulsing single tone · works with speakers"
        }
    }
}
