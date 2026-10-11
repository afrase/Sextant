// swift-tools-version: 6.2
//
// Sextant: a native macOS configurator for the ZSA Voyager.
// Clean / hexagonal layers, one target per layer or adapter group (docs/architecture.md, ADR 0006).
// Dependencies point inward only: adapters → SextantApplication → SextantDomain.

import PackageDescription

let package = Package(
    name: "Sextant",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "SextantApp", targets: ["SextantApp"])
    ],
    // Pinned community packages (ADR 0018). Exact versions: upgrades are deliberate commits.
    dependencies: [
        .package(url: "https://github.com/apple/swift-async-algorithms", exact: "1.1.7"),
        .package(url: "https://github.com/swiftlang/swift-subprocess", exact: "1.0.1"),
        .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.8.2"),
        .package(url: "https://github.com/pointfreeco/swift-clocks", exact: "1.1.1"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", exact: "1.19.6"),
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", exact: "0.65.1"),
    ],
    targets: [
        // Domain: pure Swift + Foundation.
        .target(name: "SextantDomain"),

        // Application: use cases and ports.
        .target(
            name: "SextantApplication",
            dependencies: ["SextantDomain", .product(name: "AsyncAlgorithms", package: "swift-async-algorithms")]
        ),

        // Driven adapters.
        .target(name: "SextantStorage", dependencies: ["SextantApplication", "SextantDomain"]),
        .target(name: "SextantOryx", dependencies: ["SextantApplication", "SextantDomain"]),
        .target(
            name: "SextantBuild",
            dependencies: ["SextantApplication", "SextantDomain", .product(name: "Subprocess", package: "swift-subprocess")]
        ),
        .target(name: "SextantDevice", dependencies: ["SextantApplication", "SextantDomain"]),

        // Driving adapter (UI).
        .target(name: "SextantUI", dependencies: ["SextantApplication", "SextantDomain"]),

        // Composition root.
        .executableTarget(
            name: "SextantApp",
            dependencies: [
                "SextantDomain", "SextantApplication", "SextantStorage", "SextantOryx", "SextantBuild", "SextantDevice", "SextantUI",
            ]
        ),

        // Dev tool: offscreen snapshots of real scenes for design QA (no TCC, no visible windows).
        .executableTarget(
            name: "SextantSnapshots",
            dependencies: [
                "SextantDomain", "SextantApplication", "SextantStorage", "SextantUI",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),

        .testTarget(name: "SextantDomainTests", dependencies: ["SextantDomain"]),
        .testTarget(
            name: "SextantApplicationTests",
            dependencies: ["SextantApplication", "SextantDomain", .product(name: "Clocks", package: "swift-clocks")]
        ),
        .testTarget(name: "SextantStorageTests", dependencies: ["SextantStorage", "SextantApplication", "SextantDomain"]),
        .testTarget(name: "SextantOryxTests", dependencies: ["SextantOryx", "SextantApplication", "SextantDomain"]),
        .testTarget(name: "SextantBuildTests", dependencies: ["SextantBuild", "SextantApplication", "SextantDomain"]),
        .testTarget(name: "SextantDeviceTests", dependencies: ["SextantDevice", "SextantApplication", "SextantDomain"]),
        .testTarget(
            name: "SextantUITests",
            dependencies: [
                "SextantUI", "SextantApplication", "SextantDomain",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
