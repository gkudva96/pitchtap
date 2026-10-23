// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PitchTap",
    platforms: [.macOS("14.4")],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
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
            dependencies: ["CPitchRing", "CStretch", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
            ]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
