// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeUsageWidget",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ClaudeUsageKit", targets: ["ClaudeUsageKit"]),
        .executable(name: "usage-cli", targets: ["usage-cli"]),
    ],
    targets: [
        .target(
            name: "ClaudeUsageKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "usage-cli",
            dependencies: ["ClaudeUsageKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ClaudeUsageKitTests",
            dependencies: ["ClaudeUsageKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
