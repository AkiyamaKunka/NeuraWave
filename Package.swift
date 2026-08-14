// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NeuraWave",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NeuraWave",
            path: "Sources/NeuraWave",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("MediaPlayer")]
        )
    ]
)
