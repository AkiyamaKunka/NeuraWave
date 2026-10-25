import AVFoundation
@testable import NeuraWaveCore
import XCTest

/// Rough CPU cost of the realtime render: renders 20 s of audio per
/// configuration and reports the real-time factor (lower is better). Fails
/// only if rendering gets slow enough to risk dropouts.
final class RenderPerformanceTests: XCTestCase {
    private func secondsToRender(_ audioSeconds: Double, style: ToneStyle, noise: Bool) -> Double {
        let sampleRate = 48_000.0
        let chunk: AVAudioFrameCount = 512
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk)!
        buffer.frameLength = chunk
        let state = RealtimeState()
        state.configure(preset: BrainwavePreset.byId("peak"), style: style, volume: 0.5, noiseEnabled: noise)
        state.setRunning(true)
        let chunks = Int(audioSeconds * sampleRate) / Int(chunk)
        let list = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<chunks {
            state.render(buffers: list, frameCount: Int(chunk), sampleRate: sampleRate)
        }
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
    }

    func testRenderIsFarFasterThanRealTime() {
        for style in ToneStyle.allCases {
            for noise in [false, true] {
                let audio = 20.0
                let cost = secondsToRender(audio, style: style, noise: noise)
                let factor = cost / audio
                print(String(format: "RENDER_COST %@ noise=%@ %.3f%% of real time", style.rawValue, String(noise), factor * 100))
                // Debug builds are slow; this only guards against gross regressions.
                XCTAssertLessThan(factor, 0.2)
            }
        }
    }
}
