# 16. One String Catalog, resolved from the main bundle

Status: accepted, 2026-10-11

## Context
AGENTS.md asks for String Catalogs. SwiftPM packages normally localize per module (`bundle: .module`), which would mean a catalog per target and `bundle:` arguments on every `Text`. Xcode extracts strings automatically; `swift build` does not.

## Decision
- All layers write user-facing text as `String(localized:)`, `LocalizedStringResource` or SwiftUI `Text("…")` literals with the default (main) bundle. Bare numbers use `Text(verbatim:)`.
- `Resources/Localizable.xcstrings` is the one catalog. `scripts/strings` syncs it from the `.stringsdata` files the compiler emits on every build (`xcstringstool sync`).
- `scripts/bundle` compiles the catalog into `Sextant.app/Contents/Resources`, where the main bundle finds it.
- Keycode names and legends in the domain are English data for now (shortcut, see `docs/progress.md`).

## Consequences
- Views stay plain `Text("…")`; no per-module bundles.
- Outside the `.app` (tests, `swift run`, snapshots) strings fall back to their English keys, which is the source language anyway.
- Someone has to run `scripts/strings` before a localization pass; nothing breaks if they don't.
