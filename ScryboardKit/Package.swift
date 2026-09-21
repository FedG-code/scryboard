// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ScryboardKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "ScryboardKit", targets: ["ScryboardKit"]),
    ],
    targets: [
        .target(
            name: "ScryboardKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ScryboardKitTests",
            dependencies: ["ScryboardKit"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
