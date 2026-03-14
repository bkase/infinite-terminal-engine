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
        .executableTarget(
            name: "DemoApp",
            path: "host/DemoApp",
            resources: [
                .copy("Resources"),
            ]
        ),
    ]
)
