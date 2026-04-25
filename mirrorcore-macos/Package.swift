// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MirrorCoreMac",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MirrorCoreMac",
            path: "Sources/MirrorCoreMac",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("VideoToolbox"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AVFoundation"),
            ]
        ),
    ]
)
