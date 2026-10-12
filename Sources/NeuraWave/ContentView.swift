import SwiftUI

/// The main window: holds the user's current choices (saved as they change)
/// and wires the sections in WindowSections.swift to the shared session.
struct ContentView: View {
    @State private var selected: BrainwavePreset
    @State private var style: ToneStyle
    @State private var volume: Double
    @State private var noiseOn: Bool
    @State private var minutes: Int?
    @State private var selectedProgram: FocusProgram?
    @ObservedObject private var session = SessionController.shared
    private let settings: SettingsStore

    init(settings: SettingsStore = .standard) {
        self.settings = settings
        _selected = State(initialValue: settings.preset)
        _style = State(initialValue: settings.style)
        _volume = State(initialValue: settings.volume)
        _noiseOn = State(initialValue: settings.noise)
        _minutes = State(initialValue: settings.minutes)
        _selectedProgram = State(initialValue: settings.program)
    }

    var body: some View {
        VStack(spacing: 9) {
            HeaderView(programTitle: session.programTitle, isPlaying: session.isPlaying, isPaused: session.isPaused)

            SectionLabel("Focus programs — auto-advancing sequences")
            ProgramPicker(selection: $selectedProgram, isLocked: session.isPlaying)

            let wavePreset = session.isPlaying ? session.currentPreset : selected
            WaveformView(isPlaying: session.isPlaying, isPaused: session.isPaused, beat: wavePreset.beat, color: wavePreset.color)
                .frame(height: 76)

            SectionLabel("Presets")
            PresetGrid(selected: selected, isLocked: session.isRunningProgram, onSelect: select)
            ToneControls(style: $style, noiseOn: $noiseOn, showGammaTip: selected.id == "peak" && style == .binaural)
            VolumeControl(volume: $volume)
            TransportBar(
                program: selectedProgram,
                minutes: minutes,
                remainingSeconds: session.remainingSeconds,
                isPlaying: session.isPlaying,
                isPaused: session.isPaused,
                onPickTimer: pickTimer,
                onPauseResume: session.togglePlayPause,
                onStartStop: startOrStop
            )
            if let error = session.lastError {
                ErrorBanner(message: error, onDismiss: session.clearError)
            }
        }
        .padding(14)
        .frame(minWidth: 500, minHeight: 600)
        .onChange(of: selectedProgram) { _, newValue in
            settings.program = newValue
        }
        .onChange(of: style) { _, newStyle in
            settings.style = newStyle
            // Keep whatever is playing (a program step, or a preset skipped
            // to from AirPods) and only change the style.
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
        // Presets changed outside the grid (AirPods / Control Center skip,
        // menu bar) move the selection too, including while the window was
        // closed. Program steps don't: they are the program's, not yours.
        .onChange(of: session.currentPreset.id) { _, _ in syncSelectionWithSession() }
        .onChange(of: session.isPlaying) { _, _ in syncSelectionWithSession() }
        .onAppear { syncSelectionWithSession() }
    }

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
        } else if let program = selectedProgram {
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
        settings.preset = current
    }
}
