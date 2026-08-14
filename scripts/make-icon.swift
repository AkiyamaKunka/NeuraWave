#!/usr/bin/env swift
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func drawBase(size: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let width = CGFloat(size)
    let height = CGFloat(size)

    let margin = width * 0.09
    let rect = NSRect(x: margin, y: margin, width: width - 2 * margin, height: height - 2 * margin)
    let clip = NSBezierPath(roundedRect: rect, xRadius: width * 0.22, yRadius: width * 0.22)
    clip.addClip()

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.055, green: 0.07, blue: 0.18, alpha: 1),
        NSColor(calibratedRed: 0.15, green: 0.12, blue: 0.44, alpha: 1)
    ])!
    gradient.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -70)

    let mid = height * 0.52
    let cycles: [CGFloat] = [2.0, 2.5, 3.0]
    let opacities: [CGFloat] = [1.0, 0.7, 0.45]

    for index in 0..<cycles.count {
        let amplitude = height * (0.10 - 0.025 * CGFloat(index))
        let path = NSBezierPath()
        for step in 0...200 {
            let t = CGFloat(step) / 200
            let x = margin + (width - 2 * margin) * t
            let y = mid + sin(t * .pi * 2 * cycles[index] + CGFloat(index) * 0.9) * amplitude
            if step == 0 {
                path.move(to: NSPoint(x: x, y: y))
            } else {
                path.line(to: NSPoint(x: x, y: y))
            }
        }
        path.lineWidth = width * 0.022
        path.lineCapStyle = .round
        NSColor(
            calibratedRed: 0.38 + 0.16 * CGFloat(index),
            green: 0.78 - 0.12 * CGFloat(index),
            blue: 1.0,
            alpha: opacities[index]
        ).setStroke()
        path.stroke()
    }

    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, size: Int, name: String) {
    guard let tiff = image.tiffRepresentation,
          let source = NSBitmapImageRep(data: tiff) else { return }

    let resized = NSImage(size: NSSize(width: size, height: size))
    resized.lockFocus()
    source.draw(
        in: NSRect(x: 0, y: 0, width: size, height: size),
        from: NSRect(origin: .zero, size: source.size),
        operation: .copy,
        fraction: 1.0,
        respectFlipped: false,
        hints: [:]
    )
    resized.unlockFocus()

    guard let finalTiff = resized.tiffRepresentation,
          let finalRep = NSBitmapImageRep(data: finalTiff),
          let png = finalRep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}

let base = drawBase(size: 1024)
let targets: [(Int, String)] = [
    (1024, "icon_512x512@2x.png"),
    (512, "icon_512x512.png"),
    (256, "icon_256x256.png"),
    (128, "icon_128x128.png"),
    (64, "icon_32x32@2x.png"),
    (32, "icon_32x32.png"),
    (16, "icon_16x16.png")
]

for (size, name) in targets {
    savePNG(base, size: size, name: name)
}

print(outDir)
