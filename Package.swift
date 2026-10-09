// swift-tools-version: 5.9
// Mac Screen Record — Swift Package
// Targets macOS 13+ (ScreenCaptureKit baseline). Builds natively on Apple Silicon and Intel x86_64.
// Hard fork of Free Mac Screen Recorder by penguinpecker.

import PackageDescription

let package = Package(
    name: "MacScreenRecord",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MacScreenRecord", targets: ["MacScreenRecord"]),
        .library(name: "CaptureCore", targets: ["CaptureCore"]),
        .library(name: "DeviceKit", targets: ["DeviceKit"]),
        .library(name: "EncoderKit", targets: ["EncoderKit"]),
        .library(name: "RecorderUI", targets: ["RecorderUI"]),
    ],
    targets: [
        .executableTarget(
            name: "MacScreenRecord",
            dependencies: ["CaptureCore", "DeviceKit", "EncoderKit", "RecorderUI"],
            path: "Sources/MacScreenRecord"
        ),
        .target(
            name: "CaptureCore",
            dependencies: ["EncoderKit"],
            path: "Sources/CaptureCore"
        ),
        .target(
            name: "DeviceKit",
            path: "Sources/DeviceKit"
        ),
        .target(
            name: "EncoderKit",
            path: "Sources/EncoderKit"
        ),
        .target(
            name: "RecorderUI",
            dependencies: ["CaptureCore", "DeviceKit", "EncoderKit"],
            path: "Sources/RecorderUI"
        ),
    ]
)
