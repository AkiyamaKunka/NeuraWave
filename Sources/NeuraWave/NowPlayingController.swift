import MediaPlayer

/// Now Playing / remote-control bridge: registers NeuraWave as the macOS
/// Now Playing app so AirPods gestures (single-press = toggle play/pause,
/// double-press = next/previous preset) and the Control Center widget work.
@MainActor
final class NowPlayingController {
    static let shared = NowPlayingController()

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

    func update(title: String, elapsed: TimeInterval, duration: TimeInterval?, playing: Bool, paused: Bool) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: "NeuraWave",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: playing && !paused ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]
        if let duration, duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
