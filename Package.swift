// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NeuraWave",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        // Sound engine, session logic, presets and settings, shared by the
        // macOS app and the upcoming iOS app.
        .library(name: "NeuraWaveCore", targets: ["NeuraWaveCore"])
    ],
    targets: [
        .target(
            name: "NeuraWaveCore",
            path: "Sources/NeuraWaveCore",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("MediaPlayer")]
        ),
        // The macOS menu bar app.
        .executableTarget(
            name: "NeuraWave",
            dependencies: ["NeuraWaveCore"],
            path: "Sources/NeuraWave",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Fakes for the sound output and Now Playing, shared by both test targets.
        .target(
            name: "NeuraWaveTestSupport",
            dependencies: ["NeuraWaveCore"],
            path: "Tests/NeuraWaveTestSupport",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Platform-neutral: also runs on the iOS simulator.
        .testTarget(
            name: "NeuraWaveCoreTests",
            dependencies: ["NeuraWaveCore", "NeuraWaveTestSupport"],
            path: "Tests/NeuraWaveCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The macOS app: menu bar and self-test options.
        .testTarget(
            name: "NeuraWaveTests",
            dependencies: ["NeuraWave", "NeuraWaveTestSupport"],
            path: "Tests/NeuraWaveTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
