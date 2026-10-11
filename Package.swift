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
    targets: [
        // Domain: pure Swift + Foundation.
        .target(name: "SextantDomain"),

        // Application: use cases and ports.
        .target(name: "SextantApplication", dependencies: ["SextantDomain"]),

        // Driven adapters.
        .target(name: "SextantStorage", dependencies: ["SextantApplication", "SextantDomain"]),

        // Driving adapter (UI).
        .target(name: "SextantUI", dependencies: ["SextantApplication", "SextantDomain"]),

        // Composition root.
        .executableTarget(
            name: "SextantApp",
            dependencies: ["SextantDomain", "SextantApplication", "SextantStorage", "SextantUI"]
        ),

        // Dev tool: offscreen snapshots of real scenes for design QA (no TCC, no visible windows).
        .executableTarget(
            name: "SextantSnapshots",
            dependencies: ["SextantDomain", "SextantApplication", "SextantStorage", "SextantUI"]
        ),

        .testTarget(name: "SextantDomainTests", dependencies: ["SextantDomain"]),
        .testTarget(name: "SextantApplicationTests", dependencies: ["SextantApplication", "SextantDomain"]),
        .testTarget(name: "SextantStorageTests", dependencies: ["SextantStorage", "SextantApplication", "SextantDomain"]),
        .testTarget(name: "SextantUITests", dependencies: ["SextantUI", "SextantApplication", "SextantDomain"]),
    ],
    swiftLanguageModes: [.v6]
)
