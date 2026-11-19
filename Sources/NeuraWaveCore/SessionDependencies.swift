import Foundation

/// What SessionController needs from the sound output. `AudioEngine` is the
/// real one; tests use a fake so session logic runs without audio hardware.
@MainActor
public protocol AudioOutput: AnyObject {
    /// Called when the output can't be (re)started after a device change.
    var onOutputFailure: (() -> Void)? { get set }
    /// Something may still be coming out of the speakers (incl. a stop fade).
    var isAudible: Bool { get }

    func start(preset: BrainwavePreset, style: ToneStyle, volume: Float, withNoise: Bool) -> Bool
    func switchTo(preset: BrainwavePreset, style: ToneStyle, volume: Float, withNoise: Bool)
    func update(volume: Float, noiseEnabled: Bool)
    func pause()
    func restartAfterPause() -> Bool
    func stop()
}

/// Where SessionController publishes Control Center / AirPods state.
@MainActor
public protocol NowPlayingPublishing: AnyObject {
    func update(title: String, elapsed: TimeInterval, duration: TimeInterval?, playing: Bool, paused: Bool)
    func clear()
    func setSkipEnabled(_ enabled: Bool)
}

/// A self-test driving the session: it keeps Now Playing out of the way
/// unless asked, follows program steps, and swallows remote commands so
/// results don't depend on whatever else the device is doing.
@MainActor
public protocol SessionSelfTest: AnyObject {
    var publishesNowPlaying: Bool { get }
    func programStepped(to index: Int, of count: Int, preset: BrainwavePreset)
    func remoteCommandIgnored(_ name: String)
}

extension AudioEngine: AudioOutput {}
extension NowPlayingController: NowPlayingPublishing {}
