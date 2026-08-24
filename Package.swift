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
        .executable(name: "CodexAwakeWidget", targets: ["CodexAwakeWidget"]),
    ],
    targets: [
        .target(
            name: "CodexAwakeCore",
            path: "Sources/CodexAwakeCore",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .executableTarget(
            name: "CodexAwakeApp",
            dependencies: ["CodexAwakeCore"],
            path: "Sources/CodexAwakeApp",
            swiftSettings: [
                .unsafeFlags(
                    [
                        "-emit-const-values",
                        "-Xfrontend", "-const-gather-protocols-file",
                        "-Xfrontend", "Resources/AppIntentsConstProtocols.json",
                    ]
                )
            ],
            linkerSettings: [
                .linkedFramework("LocalAuthentication")
            ]
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
        .executableTarget(
            name: "CodexAwakeWidget",
            dependencies: ["CodexAwakeCore"],
            path: "Sources/CodexAwakeWidget",
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("WidgetKit"),
            ]
        ),
        .testTarget(
            name: "CodexAwakeTests",
            dependencies: ["CodexAwakeApp", "CodexAwakeCore"],
            path: "Tests/CodexAwakeTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
