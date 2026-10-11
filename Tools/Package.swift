// swift-tools-version: 6.2
//
// Developer tools, kept out of the app's dependency graph (ADR 0018). Prebuilt, checksum-pinned binaries:
// Periphery 3.8.0's source no longer builds with Xcode 27, its release artifact does.
//   scripts/periphery   (runs `periphery scan` on the main package)

import PackageDescription

let package = Package(
    name: "SextantTools",
    platforms: [.macOS(.v26)],
    targets: [
        .binaryTarget(
            name: "Periphery",
            url: "https://github.com/peripheryapp/periphery/releases/download/3.8.0/periphery-3.8.0.artifactbundle.zip",
            checksum: "a9c7bfb1483dde1f4b660bc64183161fde3b519b7392add51ec8fe8b846cf494"
        )
    ]
)
