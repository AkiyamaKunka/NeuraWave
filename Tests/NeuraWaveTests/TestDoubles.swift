import Foundation
@testable import NeuraWave

/// Records what the session asks of the sound output; no audio hardware.
@MainActor
final class FakeAudio: AudioOutput {
    var onOutputFailure: (() -> Void)?
    var isAudible = false
    var startSucceeds = true
    var restartSucceeds = true
    private(set) var log: [String] = []
    private(set) var lastPreset: BrainwavePreset?
    private(set) var lastStyle: ToneStyle?

    func start(preset: BrainwavePreset, style: ToneStyle, volume: Float, withNoise: Bool) -> Bool {
        log.append("start \(preset.id)")
        lastPreset = preset
        lastStyle = style
        isAudible = startSucceeds
        return startSucceeds
    }

    func switchTo(preset: BrainwavePreset, style: ToneStyle, volume: Float, withNoise: Bool) {
        log.append("switch \(preset.id) \(style.rawValue)")
        lastPreset = preset
        lastStyle = style
    }

    private(set) var lastUpdatedVolume: Float?

    func update(volume: Float, noiseEnabled: Bool) {
        log.append("update \(volume)")
        lastUpdatedVolume = volume
    }
    func pause() { log.append("pause") }

    func restartAfterPause() -> Bool {
        log.append("restart")
        return restartSucceeds
    }

    func stop() {
        log.append("stop")
        isAudible = false
    }
}

@MainActor
final class FakeNowPlaying: NowPlayingPublishing {
    private(set) var title: String?
    private(set) var duration: TimeInterval?
    private(set) var paused = false
    private(set) var skipEnabled = true
    private(set) var cleared = 0
    private(set) var updates = 0

    func update(title: String, elapsed: TimeInterval, duration: TimeInterval?, playing: Bool, paused: Bool) {
        updates += 1
        self.title = title
        self.duration = duration
        self.paused = paused
    }

    func clear() {
        cleared += 1
        title = nil
    }

    func setSkipEnabled(_ enabled: Bool) { skipEnabled = enabled }
}
