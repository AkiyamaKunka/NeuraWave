import AVFoundation
import Combine
import NeuraWaveCore
import SwiftUI

/// The whole app on one screen: what's playing on top, presets or programs
/// in the middle, transport pinned to the bottom. Choices are saved as you
/// make them, so the lock screen and AirPods start exactly what you'd start.
struct PlayerView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case presets = "Presets"
        case programs = "Programs"
        var id: String { rawValue }
    }

    @ObservedObject private var session = SessionController.shared
    @State private var selected: BrainwavePreset
    @State private var style: ToneStyle
    @State private var volume: Double
    @State private var noiseOn: Bool
    @State private var minutes: Int?
    @State private var selectedProgram: FocusProgram?
    @State private var mode: Mode
    @State private var showsSettings = false
    @State private var isOnSpeaker = PlaybackAudioSession.isOnBuiltInSpeaker
    private let settings: SettingsStore

    static let timerChoices = [15, 30, 45, 60, 90]

    init(settings: SettingsStore = .standard) {
        self.settings = settings
        _selected = State(initialValue: settings.preset)
        _style = State(initialValue: settings.style)
        _volume = State(initialValue: settings.volume)
        _noiseOn = State(initialValue: settings.noise)
        _minutes = State(initialValue: settings.minutes)
        _selectedProgram = State(initialValue: settings.program)
        _mode = State(initialValue: settings.program == nil ? .presets : .programs)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    nowPlaying
                    if style == .binaural && isOnSpeaker {
                        Label("Binaural needs headphones. On the speaker, try Isochronic.", systemImage: "headphones")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(session.isPlaying)

                    switch mode {
                    case .presets:
                        presetGrid
                    case .programs:
                        programList
                    }

                    if let error = session.lastError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .onTapGesture(perform: session.clearError)
                    }
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) { transport }
            .navigationTitle("NeuraWave")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Sound settings")
                }
            }
            .sheet(isPresented: $showsSettings) {
                SettingsSheet(style: $style, volume: $volume, noiseOn: $noiseOn)
                    .presentationDetents([.medium, .large])
            }
        }
        .onChange(of: selectedProgram) { _, newValue in settings.program = newValue }
        .onChange(of: mode) { _, newMode in
            // The Programs tab with nothing picked plays nothing new; the
            // Presets tab always means "play a preset".
            if newMode == .presets {
                selectedProgram = nil
            } else if selectedProgram == nil {
                selectedProgram = FocusProgram.all.first
            }
        }
        .onChange(of: style) { _, newStyle in
            settings.style = newStyle
            session.switchPreset(
                preset: session.isPlaying ? session.currentPreset : selected,
                style: newStyle,
                volume: volume,
                withNoise: noiseOn
            )
        }
        .onChange(of: volume) { _, newValue in
            settings.volume = newValue
            session.updateLive(volume: newValue, noiseEnabled: noiseOn)
        }
        .onChange(of: noiseOn) { _, newValue in
            settings.noise = newValue
            session.updateLive(volume: volume, noiseEnabled: newValue)
        }
        // Presets skipped from AirPods or the lock screen move the selection.
        .onChange(of: session.currentPreset.id) { _, _ in syncSelectionWithSession() }
        .onReceive(
            NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification).receive(on: RunLoop.main)
        ) { _ in
            isOnSpeaker = PlaybackAudioSession.isOnBuiltInSpeaker
        }
    }

    // MARK: - Sections

    private var nowPlaying: some View {
        let preset = session.isPlaying ? session.currentPreset : (selectedProgram?.steps.first?.preset ?? selected)
        return VStack(alignment: .leading, spacing: 8) {
            WaveformView(isPlaying: session.isPlaying, isPaused: session.isPaused, beat: preset.beat, color: preset.color)
                .frame(height: 110)
                .background(RoundedRectangle(cornerRadius: 16).fill(.black.opacity(0.25)))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.isPlaying ? session.sessionTitle : (selectedProgram?.name ?? selected.name))
                        .font(.headline)
                        .lineLimit(2)
                    Text(statusLine(for: preset))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let remaining = session.remainingSeconds {
                    Text(TimeFormat.clock(remaining))
                        .font(.title2.monospacedDigit())
                        .accessibilityLabel("\(remaining / 60) minutes \(remaining % 60) seconds left")
                }
            }
        }
    }

    private func statusLine(for preset: BrainwavePreset) -> String {
        let state = session.isPaused ? "Paused" : (session.isPlaying ? "Playing" : "Ready")
        return "\(state) · \(preset.band) \(preset.beatLabel) · \(style.rawValue)"
    }

    private var presetGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(BrainwavePreset.all) { preset in
                let isSelected = preset.id == selected.id && selectedProgram == nil
                Button {
                    select(preset)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(preset.name).font(.headline)
                        Text("\(preset.band) · \(preset.beatLabel)")
                            .font(.subheadline)
                            .foregroundStyle(preset.color)
                        Text(preset.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2, reservesSpace: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(isSelected ? preset.color.opacity(0.22) : Color(.secondarySystemBackground)))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(isSelected ? preset.color : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .disabled(session.isRunningProgram)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private var programList: some View {
        VStack(spacing: 12) {
            ForEach(FocusProgram.all) { program in
                let isSelected = program.id == selectedProgram?.id
                Button {
                    selectedProgram = program
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(program.name).font(.headline)
                            Spacer()
                            Text("\(Int(program.totalSeconds / 60)) min")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Text(program.bandSummary)
                            .font(.subheadline)
                            .foregroundStyle(Color.accentColor)
                        Text(program.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(isSelected ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground)))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .disabled(session.isPlaying)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private var transport: some View {
        HStack(spacing: 12) {
            if selectedProgram == nil || (session.isPlaying && !session.isRunningProgram) {
                Menu {
                    Button("No timer") { pickTimer(nil) }
                    ForEach(Self.timerChoices, id: \.self) { choice in
                        Button("\(choice) minutes") { pickTimer(choice) }
                    }
                } label: {
                    Label(minutes.map { "\($0) min" } ?? "No timer", systemImage: "timer")
                        .frame(minHeight: 44)
                }
            }
            Spacer()
            if session.isPlaying {
                Button(action: session.togglePlayPause) {
                    Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                        .font(.title2)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(Color(.secondarySystemBackground)))
                }
                .accessibilityLabel(session.isPaused ? "Resume" : "Pause")
            }
            Button(action: startOrStop) {
                Text(session.isPlaying ? "Stop" : "Start")
                    .font(.headline)
                    .frame(minWidth: 110, minHeight: 56)
                    .foregroundStyle(.white)
                    .background(Capsule().fill(session.isPlaying ? Color.red.opacity(0.85) : Color.accentColor))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Actions

    private func select(_ preset: BrainwavePreset) {
        selected = preset
        settings.preset = preset
        session.switchPreset(preset: preset, style: style, volume: volume, withNoise: noiseOn)
    }

    private func pickTimer(_ choice: Int?) {
        minutes = choice
        settings.minutes = choice
        session.updateTimer(minutes: choice)
    }

    private func startOrStop() {
        if session.isPlaying {
            session.stop()
        } else if mode == .programs, let program = selectedProgram {
            session.startProgram(program, style: style, volume: volume, withNoise: noiseOn)
        } else {
            session.start(preset: selected, style: style, volume: volume, withNoise: noiseOn, minutes: minutes)
        }
    }

    private func syncSelectionWithSession() {
        let current = session.currentPreset
        guard session.isPlaying, !session.isRunningProgram,
              BrainwavePreset.all.contains(where: { $0.id == current.id }),
              current.id != selected.id else { return }
        selected = current
    }
}
