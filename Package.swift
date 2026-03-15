// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "InfiniteTerminalEngineHost",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "DemoApp", targets: ["DemoApp"]),
    ],
    dependencies: [],
    targets: [
        .binaryTarget(
            name: "GhosttyKit",
            path: "ghostty/macos/GhosttyKit.xcframework"
        ),
        .systemLibrary(
            name: "EngineABI",
            path: "host/EngineABI"
        ),
        .executableTarget(
            name: "DemoApp",
            dependencies: ["EngineABI", "GhosttyKit"],
            path: "host/DemoApp",
            resources: [
                .copy("Resources"),
            ],
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("AppKit"),
                .linkedFramework("IOSurface"),
                .linkedFramework("Carbon"),
                .linkedLibrary("c++"),
            ]
        ),
        .testTarget(
            name: "DemoAppTests",
            dependencies: ["DemoApp"],
            path: "host/Tests"
        ),
    ]
)
