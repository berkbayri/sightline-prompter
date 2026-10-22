// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SightlinePrompter",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SightlinePrompter", targets: ["SightlinePrompter"]),
    ],
    targets: [
        .target(
            name: "Aligner",
            path: "Sources/Aligner"
        ),
        .executableTarget(
            name: "SightlinePrompter",
            dependencies: ["Aligner"],
            path: "Sources/SightlinePrompter"
        ),
        .testTarget(
            name: "AlignerTests",
            dependencies: ["Aligner"],
            path: "Tests/AlignerTests"
        ),
    ]
)
