// swift-tools-version: 5.10
// Renders the iPhone prompter for the website from the app's own shared code (PrompterText, CameraLayout,
// ScrollEngine, PrompterTypography), so what the site shows is what the app draws. No simulator.
import PackageDescription

let package = Package(
    name: "PrompterRender",
    platforms: [.macOS(.v14)],
    dependencies: [.package(name: "SightlinePrompter", path: "../..")],
    targets: [
        .executableTarget(
            name: "prompter-render",
            dependencies: [
                .product(name: "SightlineCore", package: "SightlinePrompter"),
                .product(name: "Aligner", package: "SightlinePrompter"),
            ],
            path: "Sources"
        ),
    ]
)
