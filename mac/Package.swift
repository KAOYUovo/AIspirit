// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "AIspiritMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "Perception",
            targets: ["Perception"]
        ),
        .library(
            name: "DebugTools",
            targets: ["DebugTools"]
        ),
        .executable(
            name: "PerceptionLabApp",
            targets: ["PerceptionLabApp"]
        )
    ],
    targets: [
        .target(
            name: "Perception",
            path: "Sources/Perception"
        ),
        .target(
            name: "DebugTools",
            dependencies: ["Perception"],
            path: "Sources/DebugTools"
        ),
        .executableTarget(
            name: "PerceptionLabApp",
            dependencies: ["Perception", "DebugTools"],
            path: "Sources/PerceptionLabApp"
        ),
        .testTarget(
            name: "PerceptionTests",
            dependencies: ["Perception", "DebugTools"],
            path: "Tests/PerceptionTests"
        )
    ]
)
