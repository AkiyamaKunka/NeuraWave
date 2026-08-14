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
            id: "focus",
            name: "Deep Focus",
            band: "Beta",
            beat: 18.0,
            carrier: 264,
            detail: "13-30 Hz · alert problem solving",
            color: .orange
        ),
        BrainwavePreset(
            id: "peak",
            name: "Peak Concentration",
            band: "Gamma",
            beat: 40.0,
            carrier: 320,
            detail: "30-100 Hz · high-level concentration",
            color: .pink
        )
    ]
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
