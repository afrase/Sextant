# 8. Domain data is compiled in; visual tokens live in code

Status: accepted, 2026-10-11

## Context
The domain may use only Swift and Foundation, with no file I/O. PrototypeKit loads the settings catalog and Voyager geometry from bundled JSON. The spec also suggests asset-catalog colours and a custom `sextant.mark` symbol.

## Decision
- The settings catalog is embedded as a JSON string literal and decoded once; a test proves it decodes.
- The Voyager board definition (matrix, LED index, stagger, home row, USB ids, flash window) is a Swift table generated once from `docs/research/data/`.
- Colour tokens (bench, caps, kinds, heat ramp, combo palette) are Swift values with light, dark and high-contrast variants resolved by a dynamic `NSColor` provider, so contrast unit tests read the same values the views draw.
- Geometry uses CoreGraphics' value types (`CGPoint`, `CGSize`, `CGRect`) and nothing else from it; their `Hashable` conformances need `import CoreGraphics` in Swift 6.
- The sextant mark is a SwiftUI `Shape`, not an asset-catalog symbol. The app icon is deferred.

## Consequences
- The domain has no `Bundle.module` and no resource failures at runtime.
- `swift build` handles asset catalogs fine (probed), so this is a testability choice, not a tooling limit.
- Regenerating the board table needs the one-off script in `scripts/`.
