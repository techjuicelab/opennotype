// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenNoType",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OpenNoTypeCore", targets: ["OpenNoTypeCore"]),
        .executable(name: "LocalAudioBench", targets: ["LocalAudioBench"]),
        .executable(name: "OpenNoType", targets: ["OpenNoType"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", exact: "1.1.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.12.6"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.9.0")
    ],
    targets: [
        .target(name: "OpenNoTypeCore", dependencies: [
            .product(name: "WhisperKit", package: "WhisperKit"),
            .product(name: "FluidAudio", package: "FluidAudio")
        ]),
        .executableTarget(name: "OpenNoType", dependencies: ["OpenNoTypeCore", .product(name: "Sparkle", package: "Sparkle")], resources: [.copy("Resources/AppIcon.icns")]),
        .testTarget(name: "OpenNoTypeCoreTests", dependencies: ["OpenNoTypeCore"]),
        .testTarget(name: "OpenNoTypePlatformTests", dependencies: ["OpenNoType"]),
        .executableTarget(name: "LocalAudioBench", dependencies: ["OpenNoTypeCore"], path: "Tools/LocalAudioBench")
    ],
    swiftLanguageModes: [.v5]
)
