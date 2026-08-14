#!/usr/bin/env swift
import AppKit

guard CommandLine.arguments.count > 1,
      let image = NSImage(contentsOfFile: CommandLine.arguments[1]),
      let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff) else {
    print("usage: forensics.swift <image>")
    exit(1)
}

let width = rep.pixelsWide
let height = rep.pixelsHigh

func color(_ x: Int, _ y: Int) -> NSColor? {
    guard let c = rep.colorAt(x: x, y: y) else { return nil }
    return c
}

// 1. Bright-red pixel clusters
print("--- bright red clusters (r>170, r-g>60, r-b>60) ---")
var seen = Array(repeating: false, count: width * height)
var clusters: [(minX: Int, minY: Int, maxX: Int, maxY: Int, count: Int, sumR: Int, sumG: Int, sumB: Int)] = []
for y in stride(from: 0, to: height, by: 2) {
    for x in stride(from: 0, to: width, by: 2) {
        guard !seen[y * width + x], let c = color(x, y) else { continue }
        let r = Int(c.redComponent * 255)
        let g = Int(c.greenComponent * 255)
        let b = Int(c.blueComponent * 255)
        guard r > 170, r - g > 60, r - b > 60 else { continue }

        // flood fill
        var stack = [(x, y)]
        var minX = x, maxX = x, minY = y, maxY = y
        var count = 0, sumR = 0, sumG = 0, sumB = 0
        while let (cx, cy) = stack.popLast() {
            guard cx >= 0, cx < width, cy >= 0, cy < height, !seen[cy * width + cx],
                  let cc = color(cx, cy) else { continue }
            let cr = Int(cc.redComponent * 255)
            let cg = Int(cc.greenComponent * 255)
            let cb = Int(cc.blueComponent * 255)
            guard cr > 150, cr - cg > 40, cr - cb > 40 else { continue }
            seen[cy * width + cx] = true
            minX = min(minX, cx); maxX = max(maxX, cx)
            minY = min(minY, cy); maxY = max(maxY, cy)
            count += 1; sumR += cr; sumG += cg; sumB += cb
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                stack.append((cx + dx, cy + dy))
            }
        }
        if count >= 8 {
            clusters.append((minX, minY, maxX, maxY, count, sumR, sumG, sumB))
        }
    }
}
clusters.sort { $0.minY != $1.minY ? $0.minY < $1.minY : $0.minX < $1.minX }
for c in clusters {
    let avgR = c.sumR / c.count, avgG = c.sumG / c.count, avgB = c.sumB / c.count
    print("box x=\(c.minX)-\(c.maxX) y=\(c.minY)-\(c.maxY) px=\(c.count) avgRGB=(\(avgR),\(avgG),\(avgB))")
}

// 2. Vertical brightness profile at center to find the dark waveform band
print("--- vertical brightness profile (x=center) ---")
let probeX = width / 2
var lastBand: String? = nil
var bandStart = 0
for y in stride(from: 0, to: height, by: 4) {
    guard let c = color(probeX, y) else { continue }
    let lum = (c.redComponent + c.greenComponent + c.blueComponent) / 3
    let band: String
    switch lum {
    case ..<0.10: band = "very-dark"
    case ..<0.18: band = "dark"
    case ..<0.32: band = "medium"
    default: band = "light"
    }
    if band != lastBand {
        if let lastBand { print("y=\(bandStart)-\(y): \(lastBand)") }
        lastBand = band
        bandStart = y
    }
}
if let lastBand { print("y=\(bandStart)-\(height): \(lastBand)") }

// 3. Probe colors at selected points
print("--- point probes (x,y)=rgb ---")
for (x, y) in [(130, 110), (130, 300), (300, 130), (300, 300), (300, 450), (300, 600), (300, 900), (300, 1250), (900, 1340)] {
    if let c = color(x, y) {
        print("(\(x),\(y))=(\(Int(c.redComponent*255)),\(Int(c.greenComponent*255)),\(Int(c.blueComponent*255)))")
    }
}
