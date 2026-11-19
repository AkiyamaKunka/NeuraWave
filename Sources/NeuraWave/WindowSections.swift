import SwiftUI

// The main window's building blocks. Each takes plain values and callbacks,
// so none of them knows about SessionController or saved settings; wiring
// lives in ContentView.

struct SectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HeaderView: View {
    let programTitle: String?
    let isPlaying: Bool
    let isPaused: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("NeuraWave")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("Brainwave audio for focus, rest and sleep")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let programTitle {
                    Text(programTitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }
            }
            Spacer()
            if isPlaying {
                Label(isPaused ? "Paused" : "Playing", systemImage: isPaused ? "pause.fill" : "waveform")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(isPaused ? Color.orange.opacity(0.18) : Color.green.opacity(0.18)))
                    .foregroundStyle(isPaused ? .orange : .green)
            }
        }
    }
}

/// Focus program cards; tapping the selected one deselects it.
struct ProgramPicker: View {
    @Binding var selection: FocusProgram?
    /// Programs can't be changed while a session plays.
    let isLocked: Bool

    var body: some View {
        HStack(spacing: 8) {
            ForEach(FocusProgram.all) { program in
                let isOn = selection?.id == program.id
                Button {
                    selection = isOn ? nil : program
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(program.name)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text(program.bandSummary)
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
                .accessibilityAddTraits(isOn ? .isSelected : [])
                .disabled(isLocked)
                .opacity(isLocked ? 0.55 : 1)
            }
        }
    }
}

struct PresetGrid: View {
    let selected: BrainwavePreset
    /// A running program owns the presets.
    let isLocked: Bool
    let onSelect: (BrainwavePreset) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(BrainwavePreset.all) { preset in
                PresetCard(preset: preset, isSelected: preset.id == selected.id) {
                    onSelect(preset)
                }
                .disabled(isLocked)
                .opacity(isLocked ? 0.55 : 1)
            }
        }
    }
}

struct PresetCard: View {
    let preset: BrainwavePreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
                    Text(preset.beatLabel)
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
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Tone style picker, ambient-noise switch and the gamma tip.
struct ToneControls: View {
    @Binding var style: ToneStyle
    @Binding var noiseOn: Bool
    let showGammaTip: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Tone style", selection: $style) {
                ForEach(ToneStyle.allCases) { tone in
                    Text(tone.rawValue).tag(tone)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

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

            if showGammaTip {
                Text("Tip: at 40 Hz a binaural beat sits near the edge of perception — switch to Isochronic for the strongest gamma effect.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct VolumeControl: View {
    @Binding var volume: Double

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .foregroundStyle(.secondary)
            Slider(value: $volume, in: VolumeLevel.range)
                .accessibilityLabel("Volume")
            Image(systemName: "speaker.wave.3.fill")
                .foregroundStyle(.secondary)
        }
    }
}

/// Timer (or program length), countdown, Pause/Resume and Start/Stop.
struct TransportBar: View {
    let program: FocusProgram?
    let minutes: Int?
    let remainingSeconds: Int?
    let isPlaying: Bool
    let isPaused: Bool
    let onPickTimer: (Int?) -> Void
    let onPauseResume: () -> Void
    let onStartStop: () -> Void

    static let timerChoices = [15, 30, 45, 60, 90]

    var body: some View {
        HStack(spacing: 12) {
            if let program {
                HStack(spacing: 6) {
                    Image(systemName: "forward.fill")
                    Text("\(Int(program.totalSeconds / 60)) min program")
                        .font(.callout)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .quaternarySystemFill)))
                .fixedSize()
            } else {
                timerMenu
            }

            Spacer()

            if let remainingSeconds {
                Text(TimeFormat.clock(remainingSeconds))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if isPlaying {
                // Pause/Resume sits beside Stop, so a paused session can
                // still be stopped from the window.
                Button(action: onPauseResume) {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        .font(.headline)
                        .frame(width: 18)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Color(nsColor: .quaternarySystemFill)))
                }
                .buttonStyle(.plain)
                .help(isPaused ? "Resume" : "Pause")
                .accessibilityLabel(isPaused ? "Resume" : "Pause")
                .keyboardShortcut(.space, modifiers: [])
            }

            Button(action: onStartStop) {
                Label(isPlaying ? "Stop" : "Start", systemImage: isPlaying ? "stop.fill" : "play.fill")
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 9)
                    .background(
                        Capsule().fill(isPlaying ? AnyShapeStyle(Color.red.opacity(0.85)) : AnyShapeStyle(Color.accentColor))
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            // Space starts (and, via the Pause button, pauses/resumes);
            // ⌘. stops — the standard macOS "stop" shortcut.
            .keyboardShortcut(isPlaying ? KeyboardShortcut(".", modifiers: .command) : KeyboardShortcut(.space, modifiers: []))
            .help(isPlaying ? "Stop (⌘.)" : "Start (Space)")
        }
    }

    private var timerMenu: some View {
        Menu {
            Button("No timer") { onPickTimer(nil) }
            Divider()
            ForEach(Self.timerChoices, id: \.self) { choice in
                Button("\(choice) minutes") { onPickTimer(choice) }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "timer")
                Text(minutes.map { "\($0) min" } ?? "No timer")
                    .font(.callout)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .quaternarySystemFill)))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Dismiss", action: onDismiss)
                .buttonStyle(.link)
                .font(.caption)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.10)))
    }
}
