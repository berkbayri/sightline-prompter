// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SightlinePrompter",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .executable(name: "SightlinePrompter", targets: ["SightlinePrompter"]),
        .library(name: "SightlineCore", targets: ["SightlineCore"]),
        .library(name: "Aligner", targets: ["Aligner"]),
    ],
    targets: [
        // Platform-independent: script alignment, language data, pace.
        .target(
            name: "Aligner",
            path: "Shared/Aligner"
        ),
        // Platform-independent app logic shared by the macOS and iPhone apps.
        .target(
            name: "SightlineCore",
            dependencies: ["Aligner"],
            path: "Shared/Core"
        ),
        // macOS app: notch panel, menu bar, AppKit views.
        .executableTarget(
            name: "SightlinePrompter",
            dependencies: ["Aligner", "SightlineCore"],
            path: "macOS/App"
        ),
        .testTarget(
            name: "AlignerTests",
            dependencies: ["Aligner"],
            path: "Tests/AlignerTests"
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: ["SightlineCore"],
            path: "Tests/CoreTests"
        ),
    ]
)
