# 18. Prefer community libraries and tools; container builds by default

Status: accepted, 2026-10-11. Supersedes ADR 0014's choice of backend; ADR 0008's "domain data compiled in" is unchanged.

## Context
AGENTS.md allowed third-party dependencies only with the user's agreement. The user now prefers "to leverage libraries and community tools more than writing our own", asked for production-grade linting, and approved a concrete set of packages (2026-10-11). For firmware builds they chose the container path ("the more correct path"), wary of the ~1 GB image.

## Decision
- **Dependencies, pinned exactly in `Package.swift`:** swift-async-algorithms (live-event coalescing), swift-subprocess (toolchain processes), swift-argument-parser (dev-tool CLI), swift-clocks and swift-snapshot-testing (tests only). Sparkle at release time.
- **Linting in `scripts/check`:** swift-format (formatting plus `NeverForceUnwrap`, `NeverUseForceTry`), SwiftLint through the SimplyDanny/SwiftLintPlugins command plugin (curated opt-in rules plus path-scoped custom rules for the layer import rules SwiftPM can't enforce on system frameworks), and Periphery for unused code (prebuilt, checksum-pinned binary in `Tools/`, report-only until the MVP's APIs settle).
- **Choosing a library:** well maintained, permissive licence (MIT, Apache, BSD), pinned by exact version or checksum, and kept out of the domain unless it is pure Swift. The flasher's safety guards stay in our own tested code.
- **Build backend:** Apple Containerization with a pinned Debian image carrying ZSA's gcc 12.2.1 is the default `Toolchain` adapter. The image is downloaded only from the first build's "Set up the build tools" step (spec §7.3), with the user's consent; nothing is downloaded during development without asking. The process-based native backend stays as the fallback.

## Consequences
- Less hand-written utility code, and lint rules people already know.
- Dependency upgrades are deliberate commits; `swift package resolve` downloads them on a fresh clone.
- Periphery's source build broke on Xcode 27, hence the binary artifact; revisit when 3.9 ships.
- The Containerization package brings a large dependency tree; it lives only in `SextantBuild`.
