import Foundation
import NeuraWaveCore

/// Records what the session asks of the sound output; no audio hardware.
@MainActor
public final class FakeAudio: AudioOutput {
    public init() {}

    public var onOutputFailure: (() -> Void)?
    public var isAudible = false
    public var startSucceeds = true
    public var restartSucceeds = true
    public private(set) var log: [String] = []
    public private(set) var lastPreset: BrainwavePreset?
    public private(set) var lastStyle: ToneStyle?

    public func start(preset: BrainwavePreset, style: ToneStyle, volume: Float, withNoise: Bool) -> Bool {
        log.append("start \(preset.id)")
        lastPreset = preset
        lastStyle = style
        isAudible = startSucceeds
        return startSucceeds
    }

    public func switchTo(preset: BrainwavePreset, style: ToneStyle, volume: Float, withNoise: Bool) {
        log.append("switch \(preset.id) \(style.rawValue)")
        lastPreset = preset
        lastStyle = style
    }

    public private(set) var lastUpdatedVolume: Float?

    public func update(volume: Float, noiseEnabled: Bool) {
        log.append("update \(volume)")
        lastUpdatedVolume = volume
    }
    public func pause() { log.append("pause") }

    public func restartAfterPause() -> Bool {
        log.append("restart")
        return restartSucceeds
    }

    public func stop() {
        log.append("stop")
        isAudible = false
    }
}

@MainActor
public final class FakeNowPlaying: NowPlayingPublishing {
    public init() {}

    public private(set) var title: String?
    public private(set) var duration: TimeInterval?
    public private(set) var paused = false
    public private(set) var skipEnabled = true
    public private(set) var cleared = 0
    public private(set) var updates = 0

    public func update(title: String, elapsed: TimeInterval, duration: TimeInterval?, playing: Bool, paused: Bool) {
        updates += 1
        self.title = title
        self.duration = duration
        self.paused = paused
    }

    public func clear() {
        cleared += 1
        title = nil
    }

    public func setSkipEnabled(_ enabled: Bool) { skipEnabled = enabled }
}
