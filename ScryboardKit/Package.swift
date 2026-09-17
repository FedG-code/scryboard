// swift-tools-version: 6.2
import PackageDescription

// The one dependency in the project, and it is test-only.
//
// Apple's Command Line Tools ship neither XCTest nor Swift Testing — those come
// with Xcode — so on a CLT-only machine `swift test` has no framework to link
// against. Pinning swift-testing to the exact toolchain version fixes that
// without touching the library target: nothing here is linked into ScryboardKit,
// the container app, or the keyboard extension, so the memory ceiling that
// motivates the no-dependencies rule is unaffected.
//
// On the Mac mini, Xcode bundles its own Testing module. Drop this dependency
// (and the matching `.product` line below) there, or the two copies collide.
//
// Run the suite with:  swift test --disable-xctest
let package = Package(
    name: "ScryboardKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "ScryboardKit", targets: ["ScryboardKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-testing.git", exact: "6.2.3"),
    ],
    targets: [
        .target(
            name: "ScryboardKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ScryboardKitTests",
            dependencies: [
                "ScryboardKit",
                .product(name: "Testing", package: "swift-testing"),
            ],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
