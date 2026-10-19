// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenMessagesMac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "OpenMessagesMac",
            path: "Sources/OpenMessagesMac",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "OpenMessagesMacTests",
            dependencies: ["OpenMessagesMac"],
            path: "Tests/OpenMessagesMacTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
