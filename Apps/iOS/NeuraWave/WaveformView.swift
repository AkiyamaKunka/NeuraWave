import SwiftUI

/// Three parallel sine waves that drift while playing. The animation pauses
/// (no redraws at all) when stopped, paused, or with Reduce Motion on.
struct WaveformView: View {
    let isPlaying: Bool
    let isPaused: Bool
    let beat: Double
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let animating = isPlaying && !isPaused && !reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animating)) { context in
            Canvas { graphics, size in
                let time = context.date.timeIntervalSinceReferenceDate
                // Visual speed only loosely follows the beat; 40 Hz drawn
                // literally would just flicker.
                let speed = 0.25 + min(beat, 16) / 16 * 0.75
                for index in 0..<3 {
                    let amplitude = size.height * (0.28 - 0.07 * Double(index))
                    let cycles = 1.5 + 0.5 * Double(index)
                    let phase = (animating || isPaused ? time * speed : 0) + Double(index) * 0.9
                    var path = Path()
                    for step in 0...120 {
                        let t = Double(step) / 120
                        let x = size.width * t
                        let y = size.height / 2 - sin(t * .pi * 2 * cycles + phase) * amplitude * (isPlaying ? 1 : 0.35)
                        if step == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    graphics.stroke(
                        path,
                        with: .color(color.opacity([1.0, 0.6, 0.35][index] * (isPlaying ? 1 : 0.5))),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                }
            }
        }
        .accessibilityHidden(true)
    }
}
