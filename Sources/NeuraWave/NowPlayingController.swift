import AppKit
import MediaPlayer

/// Now Playing / remote-control bridge: registers NeuraWave as the macOS
/// Now Playing app so AirPods gestures (single-press = toggle play/pause,
/// double-press = next/previous preset) and the Control Center widget work.
@MainActor
final class NowPlayingController {
    static let shared = NowPlayingController()

    /// The app icon as Control Center / Now Playing artwork.
    private lazy var artwork: MPMediaItemArtwork? = {
        guard let icon = NSApp?.applicationIconImage else { return nil }
        return MPMediaItemArtwork(boundsSize: icon.size) { _ in icon }
    }()

    private init() {
        let center = MPRemoteCommandCenter.shared()
        center.togglePlayPauseCommand.addTarget { _ in
            Task { @MainActor in SessionController.shared.togglePlayPause() }
            return .success
        }
        center.playCommand.addTarget { _ in
            Task { @MainActor in SessionController.shared.resumeOrStart() }
            return .success
        }
        center.pauseCommand.addTarget { _ in
            Task { @MainActor in SessionController.shared.pausePlayback() }
            return .success
        }
        center.nextTrackCommand.addTarget { _ in
            Task { @MainActor in SessionController.shared.nextPreset() }
            return .success
        }
        center.previousTrackCommand.addTarget { _ in
            Task { @MainActor in SessionController.shared.previousPreset() }
            return .success
        }
    }

    /// Programs own their preset sequence, so AirPods double-press skipping
    /// is turned off while one runs.
    func setSkipEnabled(_ enabled: Bool) {
        let center = MPRemoteCommandCenter.shared()
        center.nextTrackCommand.isEnabled = enabled
        center.previousTrackCommand.isEnabled = enabled
    }

    func update(title: String, elapsed: TimeInterval, duration: TimeInterval?, playing: Bool, paused: Bool) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: "NeuraWave",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: playing && !paused ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]
        if let artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        if let duration, duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
