#if os(iOS)
import AVFoundation

/// The iOS audio session behind `AudioEngine`. The category is set once at
/// launch without activating it, so opening the app never stops your music;
/// the session goes active right before the engine starts and inactive once a
/// stop has faded out, handing audio back to whatever was playing before.
public enum PlaybackAudioSession {
    /// Playing over other apps' audio gives up the lock screen controls and
    /// AirPods gestures, because iOS only gives those to non-mixing audio.
    public static func configure(mixWithOthers: Bool) {
        try? AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .default,
            options: mixWithOthers ? [.mixWithOthers] : []
        )
    }

    /// False when another app (a call, Siri) holds audio we can't interrupt.
    static func activate() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(true)
        } catch {
            return false
        }
        // Steady tones don't need low latency: fewer, larger IO buffers save
        // energy. iOS clamps this per route (AirPods allow less).
        try? session.setPreferredIOBufferDuration(0.04)
        return true
    }

    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Binaural beats need one tone per ear; over the phone speaker they
    /// merge into a plain hum.
    public static var isOnBuiltInSpeaker: Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .builtInSpeaker }
    }
}
#endif
