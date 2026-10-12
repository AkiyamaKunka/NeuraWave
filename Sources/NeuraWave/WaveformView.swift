import AppKit
import QuartzCore
import SwiftUI

/// The animated waveform. Drawn with Core Animation: each wave is a static
/// path slid sideways by a repeating animation that runs in the system's
/// render server, so the app does no per-frame work at all (a SwiftUI
/// TimelineView/Canvas redrew and re-laid-out the view 30 times a second).
/// Hidden windows cost nothing either: Core Animation doesn't render them.
struct WaveformView: View {
    let isPlaying: Bool
    let isPaused: Bool
    let beat: Double
    let color: Color

    var body: some View {
        WaveLayers(isPlaying: isPlaying, isPaused: isPaused, beat: beat, color: NSColor(color))
            .accessibilityHidden(true) // decorative; the status text says what's playing
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.16)))
            // Keep the wave peaks inside the panel's rounded corners.
            .clipShape(RoundedRectangle(cornerRadius: 14))
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
}

/// Three parallel, non-crossing sine waves. Keeping them on the same phase
/// means they never overlap, so there is no bright "hot spot" where
/// translucent strokes stack up.
private struct WaveLayers: NSViewRepresentable {
    let isPlaying: Bool
    let isPaused: Bool
    let beat: Double
    let color: NSColor

    func makeNSView(context: Context) -> WaveLayersView {
        WaveLayersView()
    }

    func updateNSView(_ view: WaveLayersView, context: Context) {
        view.configure(isPlaying: isPlaying, isPaused: isPaused, beat: beat, color: color)
    }
}

final class WaveLayersView: NSView {
    private static let opacities: [Float] = [0.85, 0.62, 0.42]
    private static let lineWidths: [CGFloat] = [1.8, 1.5, 1.2]
    /// Two full cycles across the width.
    private static let cyclesAcross: CGFloat = 2
    private static let slideKey = "slide"

    private let waves: [CAShapeLayer] = (0..<3).map { _ in CAShapeLayer() }
    private var isPlaying = false
    private var isPaused = false
    private var beat: Double = 10
    private var color: NSColor = .systemOrange
    private var builtSize: CGSize = .zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        for (index, wave) in waves.enumerated() {
            wave.fillColor = nil
            wave.lineWidth = Self.lineWidths[index]
            wave.lineJoin = .round
            layer?.addSublayer(wave)
        }
        updateContentsScale()
    }

    // Hand-made sublayers don't inherit the backing scale; without this the
    // thin strokes would rasterize at 1x on Retina displays.
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateContentsScale()
    }

    private func updateContentsScale() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        for wave in waves { wave.contentsScale = scale }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    // SwiftUI coordinates: y grows downward, like the original Canvas.
    override var isFlipped: Bool { true }

    func configure(isPlaying: Bool, isPaused: Bool, beat: Double, color: NSColor) {
        let shapeChanged = isPlaying != self.isPlaying
        let motionChanged = shapeChanged || beat != self.beat || isPaused != self.isPaused
        self.isPlaying = isPlaying
        self.isPaused = isPaused
        self.beat = beat
        self.color = color

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Resolve the (dynamic) color for this view's light/dark appearance.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            for (index, wave) in waves.enumerated() {
                wave.strokeColor = color.withAlphaComponent(CGFloat(Self.opacities[index])).cgColor
            }
        }
        if shapeChanged { rebuildPaths() }
        CATransaction.commit()
        if motionChanged { updateMotion() }
    }

    override func layout() {
        super.layout()
        guard bounds.size != builtSize else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rebuildPaths()
        CATransaction.commit()
        updateMotion()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // Re-resolve dynamic colors for light/dark mode.
        configure(isPlaying: isPlaying, isPaused: isPaused, beat: beat, color: color)
    }

    private var wavelength: CGFloat { bounds.width / Self.cyclesAcross }

    /// Each path is one wavelength wider than the view so sliding it left
    /// by exactly one wavelength loops seamlessly.
    private func rebuildPaths() {
        let width = bounds.width
        let height = bounds.height
        guard width > 0, height > 0 else { return }
        builtSize = bounds.size
        let laneAmplitude = height * 0.16
        let amplitude = isPlaying ? laneAmplitude : 1.5
        let samplesPerWavelength = 80
        let totalSamples = samplesPerWavelength * (Int(Self.cyclesAcross) + 1)
        for (index, wave) in waves.enumerated() {
            let center = height / 2 + CGFloat(index - 1) * 2 * laneAmplitude
            let path = CGMutablePath()
            for step in 0...totalSamples {
                let x = wavelength * CGFloat(step) / CGFloat(samplesPerWavelength)
                let y = center + sin(2 * .pi * x / wavelength) * amplitude
                if step == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            wave.frame = bounds
            wave.path = path
        }
    }

    /// Playing: slide left forever at the original speed (phase advancing
    /// `beat` radians per second). Paused: freeze where it is. Idle: still.
    private func updateMotion() {
        for wave in waves {
            guard isPlaying, wavelength > 0, beat > 0 else {
                wave.removeAnimation(forKey: Self.slideKey)
                resetTiming(wave)
                continue
            }
            if wave.animation(forKey: Self.slideKey) == nil
                || animatedBeat != beat || animatedWavelength != wavelength {
                // Restart at the same point in the cycle, so resizing the
                // window or changing preset doesn't snap the wave back.
                let fraction = cycleFraction(of: wave)
                resetTiming(wave)
                let slide = slideAnimation()
                slide.timeOffset = fraction * slide.duration
                wave.add(slide, forKey: Self.slideKey)
            }
            if isPaused, wave.speed != 0 {
                // Freeze the presentation where it is.
                let pausedTime = wave.convertTime(CACurrentMediaTime(), from: nil)
                wave.speed = 0
                wave.timeOffset = pausedTime
            } else if !isPaused, wave.speed == 0 {
                // Carry on from the frozen point.
                let pausedTime = wave.timeOffset
                wave.speed = 1
                wave.timeOffset = 0
                wave.beginTime = 0
                wave.beginTime = wave.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
            }
        }
        animatedBeat = beat
        animatedWavelength = wavelength
    }

    private var animatedBeat: Double = 0
    private var animatedWavelength: CGFloat = 0

    /// Where the wave currently is in its one-wavelength slide, 0..<1.
    private func cycleFraction(of wave: CALayer) -> Double {
        guard animatedWavelength > 0,
              let offset = wave.presentation()?.value(forKeyPath: "transform.translation.x") as? CGFloat else {
            return 0
        }
        let fraction = Double(-offset / animatedWavelength)
        return min(max(fraction, 0), 0.999)
    }

    private func resetTiming(_ wave: CALayer) {
        wave.speed = 1
        wave.timeOffset = 0
        wave.beginTime = 0
    }

    private func slideAnimation() -> CABasicAnimation {
        let slide = CABasicAnimation(keyPath: "transform.translation.x")
        slide.fromValue = 0
        slide.toValue = -wavelength
        // One wavelength is 2π of phase; the phase advances `beat` rad/s.
        slide.duration = 2 * .pi / beat
        slide.repeatCount = .infinity
        slide.isRemovedOnCompletion = false
        return slide
    }
}
