import SwiftUI

struct WaveformView: View {
    let isPlaying: Bool
    let beat: Double
    let color: Color

    var body: some View {
        Group {
            if isPlaying {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    waveCanvas(time: timeline.date.timeIntervalSinceReferenceDate)
                }
            } else {
                // Idle: a static canvas — no 30 fps timeline ticking for nothing.
                waveCanvas(time: 0)
            }
        }
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.16)))
        .overlay {
            if !isPlaying {
                Text("Press Start to play")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func waveCanvas(time: TimeInterval) -> some View {
        Canvas { context, size in
            let mid = size.height / 2
            let playing = isPlaying

            for index in 0..<3 {
                var path = Path()
                // Three parallel, non-crossing waves. Keeping them on the
                // same phase means they never overlap, so there is no
                // bright "hot spot" where translucent strokes stack up.
                let laneAmplitude = size.height * 0.16
                let center = mid + CGFloat(Double(index) - 1.0) * 2.0 * laneAmplitude
                let amplitude = playing ? laneAmplitude : 1.5
                let phase = time * beat
                let opacity = [0.85, 0.62, 0.42][index]

                for step in 0...160 {
                    let x = size.width * Double(step) / 160
                    let t = Double(step) / 160
                    let y = center + sin(t * .pi * 4 + phase) * amplitude
                    if step == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }

                context.stroke(
                    path,
                    with: .color(color.opacity(opacity)),
                    lineWidth: [1.8, 1.5, 1.2][index]
                )
            }
        }
    }
}
