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
        Self.route(center.togglePlayPauseCommand, "togglePlayPause") { $0.togglePlayPause() }
        Self.route(center.playCommand, "play") { $0.resumeOrStart() }
        Self.route(center.pauseCommand, "pause") { $0.pausePlayback() }
        Self.route(center.nextTrackCommand, "next") { $0.nextPreset() }
        Self.route(center.previousTrackCommand, "previous") { $0.previousPreset() }
    }

    /// Forward a remote command to the session on the main actor (unless a
    /// self-test is isolating the session from outside input).
    private static func route(
        _ command: MPRemoteCommand,
        _ name: String,
        _ action: @escaping @MainActor @Sendable (SessionController) -> Void
    ) {
        command.addTarget { _ in
            Task { @MainActor in
                let session = SessionController.shared
                if session.shouldHandleRemoteCommand(name) {
                    action(session)
                }
            }
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
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        // macOS reads the play/pause state from playbackState (the rate in
        // nowPlayingInfo alone isn't enough for Control Center / AirPods).
        center.playbackState = playing && !paused ? .playing : .paused
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }
}
