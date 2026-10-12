import AppKit
import SwiftUI

struct WaveformView: View {
    let isPlaying: Bool
    let isPaused: Bool
    let beat: Double
    let color: Color
    /// False while the window is hidden, minimized or fully covered. A
    /// hidden window (e.g. after a login launch, playing from the menu bar)
    /// would otherwise keep redrawing at 30 fps for nobody (~7% CPU).
    @State private var isOnScreen = true

    var body: some View {
        // One timeline that simply stops while idle or paused: no 30 fps
        // ticking for nothing, and a paused wave freezes where it was
        // instead of snapping back to its starting phase.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying || isPaused || !isOnScreen)) { timeline in
            waveCanvas(time: timeline.date.timeIntervalSinceReferenceDate)
        }
        .background(WindowOcclusionReader(isOnScreen: $isOnScreen))
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.16)))
        .overlay {
            if !isPlaying {
                Text("Press Start to play")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if isPaused {
                Text("Paused")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
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

/// Reports whether the hosting window is actually visible on screen
/// (`NSWindow.occlusionState`), tracking show/hide, minimize and covering.
private struct WindowOcclusionReader: NSViewRepresentable {
    @Binding var isOnScreen: Bool

    func makeNSView(context: Context) -> ObservingView {
        let view = ObservingView()
        view.onChange = { visible in
            if isOnScreen != visible { isOnScreen = visible }
        }
        return view
    }

    func updateNSView(_ nsView: ObservingView, context: Context) {}

    final class ObservingView: NSView {
        var onChange: ((Bool) -> Void)?
        // Set and cleared on the main thread; read once more in deinit.
        nonisolated(unsafe) private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer {
                NotificationCenter.default.removeObserver(observer)
                self.observer = nil
            }
            guard let window else { return }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.report() }
            }
            report()
        }

        private func report() {
            onChange?(window?.occlusionState.contains(.visible) ?? false)
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}
