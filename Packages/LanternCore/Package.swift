// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LanternCore",
    platforms: [.iOS("27.0"), .macOS("26.0")],
    products: [
        .library(name: "LanternCore", targets: ["LanternCore"])
    ],
    targets: [
        .target(
            name: "LanternCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "LanternCoreTests",
            dependencies: ["LanternCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
