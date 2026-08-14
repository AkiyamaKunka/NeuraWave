#!/usr/bin/env swift
import AppKit
import Vision

guard CommandLine.arguments.count > 1,
      let image = NSImage(contentsOfFile: CommandLine.arguments[1]),
      let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff) else {
    print("usage: inspect-image.swift <image>")
    exit(1)
}

let width = rep.pixelsWide
let height = rep.pixelsHigh
print("size: \(width)x\(height)")

// OCR with bounding boxes
if let cgImage = rep.cgImage {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    let handler = VNImageRequestHandler(cgImage: cgImage)
    try? handler.perform([request])

    print("--- OCR ---")
    if let observations = request.results {
        for obs in observations {
            guard let candidate = obs.topCandidates(1).first else { continue }
            let box = obs.boundingBox
            let x = Int(box.origin.x * CGFloat(width))
            let yTop = Int((1 - box.origin.y - box.height) * CGFloat(height))
            let w = Int(box.width * CGFloat(width))
            let h = Int(box.height * CGFloat(height))
            print("[x=\(x) y=\(yTop) w=\(w) h=\(h)] \(candidate.string)")
        }
    }
}

// Color map
struct Bucket: OptionSet, Hashable {
    let rawValue: Int
    static let red = Bucket(rawValue: 1 << 0)
    static let pink = Bucket(rawValue: 1 << 1)
    static let orange = Bucket(rawValue: 1 << 2)
    static let yellow = Bucket(rawValue: 1 << 3)
    static let green = Bucket(rawValue: 1 << 4)
    static let teal = Bucket(rawValue: 1 << 5)
    static let indigo = Bucket(rawValue: 1 << 6)
    static let blue = Bucket(rawValue: 1 << 7)
}

func classify(r: Int, g: Int, b: Int) -> Bucket {
    switch true {
    case r > 170 && g < 120 && b < 120: return .red
    case r > 200 && g < 170 && b > 140: return .pink
    case r > 200 && g > 100 && g < 200 && b < 90: return .orange
    case r > 200 && g > 180 && b < 120: return .yellow
    case g > 140 && r < 120 && b < 120: return .green
    case g > 120 && b > 120 && r < 100: return .teal
    case b > 140 && r < 150 && g < 120: return .indigo
    case b > 190 && r < 100 && g < 190: return .blue
    default: return []
    }
}

func bucketChar(_ bucket: Bucket) -> Character {
    if bucket.contains(.red) { return "R" }
    if bucket.contains(.pink) { return "P" }
    if bucket.contains(.orange) { return "O" }
    if bucket.contains(.yellow) { return "Y" }
    if bucket.contains(.green) { return "G" }
    if bucket.contains(.teal) { return "T" }
    if bucket.contains(.indigo) { return "I" }
    if bucket.contains(.blue) { return "B" }
    return "."
}

let cols = 40
let rows = 40
let cellW = max(width / cols, 1)
let cellH = max(height / rows, 1)

print("--- color map (40x40) ---")
for row in 0..<rows {
    var line = ""
    for col in 0..<cols {
        var counts: [Bucket: Int] = [:]
        for y in stride(from: row * cellH, to: min((row + 1) * cellH, height), by: 3) {
            for x in stride(from: col * cellW, to: min((col + 1) * cellW, width), by: 3) {
                let color = rep.colorAt(x: x, y: y)
                guard let color else { continue }
                let r = Int(color.redComponent * 255)
                let g = Int(color.greenComponent * 255)
                let b = Int(color.blueComponent * 255)
                let bucket = classify(r: r, g: g, b: b)
                if !bucket.isEmpty {
                    counts[bucket, default: 0] += 1
                }
            }
        }
        if let dominant = counts.max(by: { $0.value < $1.value })?.key {
            line.append(bucketChar(dominant))
        } else {
            line.append(".")
        }
    }
    print(line)
}
