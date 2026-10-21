// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PitchTap",
    platforms: [.macOS("14.4")],
    targets: [
        .target(name: "CPitchRing"),
        .target(
            name: "CStretch",
            exclude: ["vendor/README.md", "vendor/signalsmith-stretch/LICENSE.txt",
                      "vendor/signalsmith-linear/LICENSE.txt"],
            cxxSettings: [.headerSearchPath("vendor")]
        ),
        .executableTarget(
            name: "PitchTap",
            dependencies: ["CPitchRing", "CStretch"],
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
            ]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
