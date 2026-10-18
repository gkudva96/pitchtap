// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PitchTap",
    platforms: [.macOS("14.4")],
    targets: [
        .target(name: "CPitchRing"),
        .executableTarget(
            name: "PitchTap",
            dependencies: ["CPitchRing"],
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
            ]
        ),
    ]
)
