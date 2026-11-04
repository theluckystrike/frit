// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Glaze",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GlazeCore", targets: ["GlazeCore"]),
        .executable(name: "GlazeApp", targets: ["GlazeApp"]),
    ],
    targets: [
        .target(
            name: "GlazeCore",
            exclude: ["Resources/README-data.md"],
            resources: [
                .process("Resources/oxides.json"),
                .process("Resources/materials.json"),
            ]
        ),
        .executableTarget(
            name: "GlazeApp",
            dependencies: ["GlazeCore"]
        ),
        .testTarget(
            name: "GlazeCoreTests",
            dependencies: ["GlazeCore"],
            // Test-only reference data (Glazy export, CC BY-NC-SA 4.0). Read from the source tree; never bundled.
            exclude: ["Fixtures"]
        ),
    ]
)
