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
    targets: [
        .systemLibrary(
            name: "EngineABI",
            path: "host/EngineABI"
        ),
        .executableTarget(
            name: "DemoApp",
            dependencies: ["EngineABI"],
            path: "host/DemoApp",
            resources: [
                .copy("Resources"),
            ],
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("AppKit"),
            ]
        ),
        .testTarget(
            name: "DemoAppTests",
            dependencies: ["DemoApp"],
            path: "host/Tests"
        ),
    ]
)
