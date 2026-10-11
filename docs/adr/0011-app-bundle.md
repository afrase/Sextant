# 11. App bundle built with SwiftPM and a script, no Xcode project

Status: accepted, 2026-10-11

## Context
Sextant must ship as a real `.app` with hardened runtime, minimal entitlements, Developer ID signing and notarization, built from the command line with no third-party tools. The options were a thin Xcode project or SwiftPM plus a bundling script.

## Decision
`scripts/bundle` runs `swift build -c release --product SextantApp`, assembles `Sextant.app/Contents/{MacOS/Sextant, Info.plist, Resources/*.bundle}`, and signs with `codesign --options runtime --entitlements Sextant.entitlements --sign "$SEXTANT_SIGN_IDENTITY"` (ad-hoc `-` when unset). `scripts/notarize` wraps `notarytool` and `stapler` and is run only by the user. The app is not sandboxed for now (research 00 §6), so the entitlements file is empty.

## Consequences
- Probed on this toolchain: `swift build` compiles String Catalogs and asset catalogs, and SwiftPM's resource accessor finds bundles in `Contents/Resources`, so signing stays valid.
- No `.pbxproj` to maintain, and the package is the only build definition.
- No Xcode-managed signing, capabilities UI or app icon asset; the icon will be an `.icns` made with `iconutil` when it exists.
