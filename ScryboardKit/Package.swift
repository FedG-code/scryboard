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
        .library(name: "ScryboardUI", targets: ["ScryboardUI"]),
    ],
    targets: [
        // Foundation only. Portable to Kotlin.
        .target(
            name: "ScryboardKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // ImageIO and friends: image fetching, downsampling and caching, shared
        // by the container app and the keyboard extension.
        .target(
            name: "ScryboardUI",
            dependencies: ["ScryboardKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ScryboardKitTests",
            dependencies: ["ScryboardKit"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ScryboardUITests",
            dependencies: ["ScryboardUI"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
