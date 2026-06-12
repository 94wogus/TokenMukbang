// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TokenMukbang",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TokenMukbangKit", targets: ["TokenMukbangKit"]),
        .executable(name: "usage-cli", targets: ["usage-cli"]),
    ],
    targets: [
        .target(
            name: "TokenMukbangKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "usage-cli",
            dependencies: ["TokenMukbangKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TokenMukbangKitTests",
            dependencies: ["TokenMukbangKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
