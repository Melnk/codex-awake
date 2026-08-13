// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexAwake",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "CodexAwakeCore", targets: ["CodexAwakeCore"]),
        .executable(name: "CodexAwake", targets: ["CodexAwakeApp"]),
        .executable(name: "CodexAwakeClosedLidHelper", targets: ["CodexAwakeClosedLidHelper"]),
        .executable(name: "CodexAwakeProtocolProbe", targets: ["CodexAwakeProtocolProbe"]),
    ],
    targets: [
        .target(
            name: "CodexAwakeCore",
            path: "Sources/CodexAwakeCore",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .executableTarget(
            name: "CodexAwakeApp",
            dependencies: ["CodexAwakeCore"],
            path: "Sources/CodexAwakeApp"
        ),
        .executableTarget(
            name: "CodexAwakeClosedLidHelper",
            dependencies: ["CodexAwakeCore"],
            path: "Sources/CodexAwakeClosedLidHelper"
        ),
        .executableTarget(
            name: "CodexAwakeProtocolProbe",
            dependencies: ["CodexAwakeCore"],
            path: "Sources/CodexAwakeProtocolProbe"
        ),
        .testTarget(
            name: "CodexAwakeTests",
            dependencies: ["CodexAwakeApp", "CodexAwakeCore"],
            path: "Tests/CodexAwakeTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
