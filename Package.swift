// swift-tools-version:6.2
import Foundation
import PackageDescription

// whisper.cpp is built by scripts/build-whisper.sh into vendor/whisper (static, Metal).
let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let whisperLibDir = "\(packageRoot)/vendor/whisper/lib"

let package = Package(
    name: "LocalFlow",
    platforms: [.macOS(.v26)],
    targets: [
        .systemLibrary(name: "CWhisper", path: "Sources/CWhisper"),
        .executableTarget(
            name: "LocalFlow",
            dependencies: ["CWhisper"],
            path: "Sources/LocalFlow",
            linkerSettings: [
                .unsafeFlags(["-L", whisperLibDir]),
                .linkedLibrary("whisper"),
                .linkedLibrary("ggml"),
                .linkedLibrary("ggml-base"),
                .linkedLibrary("ggml-cpu"),
                .linkedLibrary("ggml-metal"),
                .linkedLibrary("ggml-blas"),
                .linkedLibrary("c++"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Foundation"),
            ]
        ),
    ]
)
