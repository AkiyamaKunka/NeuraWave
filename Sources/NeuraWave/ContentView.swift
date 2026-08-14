import Foundation
import SwiftUI

struct ContentView: View {
    @State private var selected = BrainwavePreset.all[3]
    @State private var style: ToneStyle = .binaural
    @State private var volume: Double = 0.55
    @State private var noiseOn = false
    @State private var minutes: Int? = nil
    @State private var selectedProgram: FocusProgram?
    @StateObject private var session = SessionController.shared

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]
    private let durations = [15, 30, 45, 60, 90]

    init() {
        let defaults = UserDefaults.standard
        let savedPreset = defaults.string(forKey: "preset")
        _selected = State(initialValue: BrainwavePreset.all.first { $0.id == savedPreset } ?? BrainwavePreset.byId("focus"))
        _style = State(initialValue: ToneStyle(rawValue: defaults.string(forKey: "style") ?? "") ?? .binaural)
        _volume = State(initialValue: defaults.object(forKey: "volume") as? Double ?? 0.55)
        _noiseOn = State(initialValue: defaults.bool(forKey: "noise"))
        let savedMinutes = defaults.integer(forKey: "minutes")
        _minutes = State(initialValue: savedMinutes > 0 ? savedMinutes : nil)
        _selectedProgram = State(initialValue: FocusProgram.all.first { $0.id == defaults.string(forKey: "program") })
    }

    var body: some View {
        VStack(spacing: 9) {
            header

            sectionLabel("Focus programs — auto-advancing sequences")
            programRow

            WaveformView(isPlaying: session.isPlaying, beat: selected.beat, color: selected.color)
                .frame(height: 76)

            sectionLabel("Presets")
            presetGrid
            styleRow
            volumeRow
            footerRow
            errorRow
        }
        .padding(14)
        .frame(minWidth: 500, minHeight: 600)
        .onChange(of: volume) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: "volume")
            session.updateLive(volume: newValue, noiseEnabled: noiseOn)
        }
        .onChange(of: noiseOn) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: "noise")
            session.updateLive(volume: volume, noiseEnabled: newValue)
        }
    }

    @ViewBuilder
    private var errorRow: some View {
        if let error = session.lastError {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Dismiss") { session.clearError() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(0.10))
            )
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("NeuraWave")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("Brainwave audio for focus, rest and sleep")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let title = session.programTitle {
                    Text(title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }
            }
            Spacer()
            if session.isPlaying {
                Label("Playing", systemImage: "waveform")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.green.opacity(0.18)))
                    .foregroundStyle(.green)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func beatLabel(_ beat: Double) -> String {
        let trimmed = beat == beat.rounded() ? String(Int(beat)) : String(format: "%.1f", beat)
        return trimmed + " Hz"
    }

    private var programRow: some View {
        HStack(spacing: 8) {
            ForEach(FocusProgram.all) { program in
                let isOn = selectedProgram?.id == program.id
                Button {
                    selectedProgram = isOn ? nil : program
                    UserDefaults.standard.set(selectedProgram?.id ?? "", forKey: "program")
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(program.name)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text(programSummary(program))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(width: 150, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isOn ? Color.accentColor.opacity(0.16) : Color(nsColor: .quaternarySystemFill))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isOn ? Color.accentColor : .clear, lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .disabled(session.isPlaying)
                .opacity(session.isPlaying ? 0.55 : 1)
            }
        }
    }

    private func programSummary(_ program: FocusProgram) -> String {
        program.steps.map { $0.preset.band }.joined(separator: "→")
    }

    private var presetGrid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(BrainwavePreset.all) { preset in
                presetCard(preset)
            }
        }
    }

    private func presetCard(_ preset: BrainwavePreset) -> some View {
        let isSelected = selected.id == preset.id
        return Button {
            selected = preset
            UserDefaults.standard.set(preset.id, forKey: "preset")
            session.switchPreset(
                preset: preset,
                style: style,
                volume: volume,
                withNoise: noiseOn
            )
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(preset.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(preset.color)
                    }
                }
                HStack(spacing: 6) {
                    Text(preset.band)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(preset.color.opacity(0.22)))
                        .foregroundStyle(preset.color)
                    Text(beatLabel(preset.beat))
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(preset.color)
                }
                Text(preset.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .quaternarySystemFill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? preset.color : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }

    private var styleRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Tone style", selection: $style) {
                ForEach(ToneStyle.allCases) { tone in
                    Text(tone.rawValue).tag(tone)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: style) { _, newStyle in
                UserDefaults.standard.set(newStyle.rawValue, forKey: "style")
                session.switchPreset(
                    preset: selected,
                    style: newStyle,
                    volume: volume,
                    withNoise: noiseOn
                )
            }

            HStack {
                Text(style.tip)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle(isOn: $noiseOn) {
                    Label("Ambient noise", systemImage: "wind")
                        .font(.caption)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            if selected.id == "peak" && style == .binaural {
                Text("Tip: at 40 Hz a binaural beat sits near the edge of perception — switch to Isochronic for the strongest gamma effect.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var volumeRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .foregroundStyle(.secondary)
            Slider(value: $volume, in: 0.05...1.0)
            Image(systemName: "speaker.wave.3.fill")
                .foregroundStyle(.secondary)
        }
    }

    private var footerRow: some View {
        HStack(spacing: 12) {
            if let program = selectedProgram {
                HStack(spacing: 6) {
                    Image(systemName: "forward.fill")
                    Text("\(Int(program.totalSeconds / 60)) min program")
                        .font(.callout)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .quaternarySystemFill))
                )
                .fixedSize()
            } else {
                Menu {
                    Button("No timer") {
                        minutes = nil
                        UserDefaults.standard.set(0, forKey: "minutes")
                    }
                    Divider()
                    ForEach(durations, id: \.self) { duration in
                        Button("\(duration) minutes") {
                            minutes = duration
                            UserDefaults.standard.set(duration, forKey: "minutes")
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "timer")
                        Text(minutes.map { "\($0) min" } ?? "No timer")
                            .font(.callout)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .quaternarySystemFill))
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Spacer()

            if let remaining = session.remainingSeconds {
                Text(Self.timeString(remaining))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Button {
                if session.isPlaying {
                    session.stop()
                } else if let program = selectedProgram {
                    session.startProgram(program, style: style, volume: volume, withNoise: noiseOn)
                } else {
                    session.start(
                        preset: selected,
                        style: style,
                        volume: volume,
                        withNoise: noiseOn,
                        minutes: minutes
                    )
                }
            } label: {
                Label(
                    session.isPlaying ? "Stop" : "Start",
                    systemImage: session.isPlaying ? "stop.fill" : "play.fill"
                )
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.vertical, 9)
                .background(
                    Capsule().fill(
                        session.isPlaying
                            ? AnyShapeStyle(Color.red.opacity(0.85))
                            : AnyShapeStyle(Color.accentColor)
                    )
                )
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
    }

    private static func timeString(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

