import AVFoundation
import NeuraWaveCore

/// Applies iOS audio-session events to the shared session: calls and Siri
/// pause it (and resume it when iOS says so), and taking AirPods out or
/// unplugging headphones pauses instead of moving the tones to the speaker.
@MainActor
final class AudioSessionEvents {
    static let shared = AudioSessionEvents()

    private let session = SessionController.shared
    /// Only a session that the interruption paused resumes by itself.
    private var pausedByInterruption = false
    private var observers: [NSObjectProtocol] = []

    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        let audioSession = AVAudioSession.sharedInstance()
        observers = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: audioSession, queue: .main) { note in
                let info = Self.interruption(from: note)
                MainActor.assumeIsolated { self.handleInterruption(info) }
            },
            center.addObserver(forName: AVAudioSession.routeChangeNotification, object: audioSession, queue: .main) { note in
                let reason = Self.routeChangeReason(from: note)
                MainActor.assumeIsolated { self.handleRouteChange(reason) }
            },
            center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: audioSession, queue: .main) { _ in
                MainActor.assumeIsolated { self.handleMediaServicesReset() }
            }
        ]
    }

    private nonisolated static func interruption(from note: Notification) -> (began: Bool, shouldResume: Bool) {
        let info = note.userInfo ?? [:]
        let type = (info[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
        let options = AVAudioSession.InterruptionOptions(rawValue: info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
        return (type == .began, options.contains(.shouldResume))
    }

    private nonisolated static func routeChangeReason(from note: Notification) -> AVAudioSession.RouteChangeReason? {
        (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init)
    }

    private func handleInterruption(_ info: (began: Bool, shouldResume: Bool)) {
        if info.began {
            guard session.isPlaying, !session.isPaused else { return }
            pausedByInterruption = true
            session.pausePlayback()
        } else {
            defer { pausedByInterruption = false }
            if pausedByInterruption, info.shouldResume, session.isPaused {
                session.resumePlayback()
            }
        }
    }

    private func handleRouteChange(_ reason: AVAudioSession.RouteChangeReason?) {
        guard reason == .oldDeviceUnavailable, session.isPlaying, !session.isPaused else { return }
        pausedByInterruption = false
        session.pausePlayback()
    }

    /// Rare (the system's audio daemon restarted): everything audio is
    /// gone, so end the session cleanly rather than "play" silence.
    private func handleMediaServicesReset() {
        session.stop()
        PlaybackAudioSession.configure(mixWithOthers: AppSettings.mixWithOthers)
    }
}
