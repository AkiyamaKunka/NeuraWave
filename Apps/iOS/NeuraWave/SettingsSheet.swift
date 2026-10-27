import NeuraWaveCore
import SwiftUI

/// Sound settings plus the one iPhone-only choice: whether to play over
/// other apps' audio.
struct SettingsSheet: View {
    @Binding var style: ToneStyle
    @Binding var volume: Double
    @Binding var noiseOn: Bool
    @AppStorage(AppSettings.mixWithOthersKey) private var mixWithOthers = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Tone style", selection: $style) {
                        ForEach(ToneStyle.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Tone")
                } footer: {
                    Text(style.tip)
                }

                Section("Sound") {
                    HStack(spacing: 12) {
                        Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                        Slider(value: $volume, in: VolumeLevel.range)
                            .accessibilityLabel("Volume")
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                    }
                    Toggle(isOn: $noiseOn) {
                        Label("Ambient noise", systemImage: "wind")
                    }
                }

                Section {
                    Toggle("Play over my music", isOn: $mixWithOthers)
                } footer: {
                    Text("Mixes with other apps' audio. The lock screen and AirPods controls then stay with the other app.")
                }

                Section {
                    Text("NeuraWave is not a medical device and makes no medical claims. If you have epilepsy or are sensitive to flashing or pulsing stimuli, talk to a doctor before using Isochronic tones.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Sound")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: mixWithOthers) { _, newValue in
                PlaybackAudioSession.configure(mixWithOthers: newValue)
            }
        }
    }
}
