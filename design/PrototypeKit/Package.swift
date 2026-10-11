// swift-tools-version: 6.2
//
// PrototypeKit: the shared, visually neutral foundation for Sextant's UI prototypes.
// Model + legends + keycode catalog + Voyager geometry + mock data + editor store + offscreen snapshots.
// No third-party dependencies. See Sources/PrototypeKit/PrototypeKit.swift for an overview.

import PackageDescription

let package = Package(
    name: "PrototypeKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PrototypeKit", targets: ["PrototypeKit"]),
        .executable(name: "PrototypeKitDemo", targets: ["PrototypeKitDemo"]),
    ],
    targets: [
        .target(
            name: "PrototypeKit",
            resources: [
                .copy("Resources/my-layout-KlgM7-40xJ7M.json"),
                .copy("Resources/voyager-geometry.json"),
                .copy("Resources/settings-catalog.json"),
            ]
        ),
        .executableTarget(
            name: "PrototypeKitDemo",
            dependencies: ["PrototypeKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
