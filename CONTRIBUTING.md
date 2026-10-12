# Contributing to Sextant

Thanks for your interest. Sextant writes firmware to people's keyboards, so the bar is high and the rules below are firm. For anything larger than a small fix, open an issue first so we can agree on the approach.

## Before you open a pull request

Run the quality gate and make it pass with no warnings:

```sh
scripts/check
```

It runs `swift format lint --strict`, SwiftLint (code quality and the layer import rules), a build with warnings as errors, and the tests. Locally it also prints a Periphery unused-code report; findings there don't fail the gate. CI runs the same script on macOS 26 with Xcode 26.6.

## Code

- **Swift 6 with complete strict concurrency.** Domain types are `Sendable` value types, device I/O lives in actors, UI state is `@MainActor`. Use async/await and `AsyncStream` with structured concurrency.
- **Dependencies point inward only** (clean / hexagonal architecture, [docs/architecture.md](docs/architecture.md)). Each layer is its own SwiftPM target, so a wrong import fails to compile:
  - `SextantDomain`: pure Swift and Foundation. No SwiftUI, AppKit, IOKit, networking or file I/O.
  - `SextantApplication`: use cases, and the ports (protocols) they reach the outside world through.
  - `SextantStorage`, `SextantOryx`, `SextantBuild`, `SextantDevice`: adapters that implement the ports.
  - `SextantUI`: SwiftUI views and `@Observable` view models that call use cases, never adapters.
  - `SextantApp`: the composition root, the only place that wires adapters to ports.
- **No singletons or global mutable state.** Inject dependencies through initializers.
- **Typed errors**, with `LocalizedError` for anything the user sees. No `try!` or force-unwraps outside tests.
- **Tests use Swift Testing** (`import Testing`, `@Test`, `#expect`). Domain and use cases get unit tests with in-memory fakes of the ports; adapters get contract tests.
- **User-facing text** goes in the String Catalog (run `scripts/strings` after changing it) and uses US English. Custom views need accessibility labels.
- **Known limits are written down.** When code takes a deliberate shortcut, say so where it lives: `// shortcut: <the limit>, <when to upgrade>`. The project tracks these instead of TODOs.
- **New dependencies need a discussion first.** Packages are pinned to exact versions and must have permissive licenses (ADR 0018).

## Decisions

Every significant decision gets an architecture decision record in [docs/adr/](docs/adr/), numbered after the last one and indexed in [docs/decisions.md](docs/decisions.md). An accepted ADR is never rewritten; a changed decision gets a new ADR that supersedes it.

## Code that talks to the keyboard

- Anything that writes to a keyboard (raw HID, RGB, entering the bootloader, DFU) must be covered by tests against a fake transport that exercise every guard, including the refusals.
- Never send anything to a real keyboard without the owner's explicit OK for that action. Read-only USB enumeration is fine. Hardware access in the app stays off by default.
- The flasher's guards are not negotiable: writes only within `[0x08002000, 0x08042000)`, no mass erase, a DFU suffix that matches the connected bootloader, an md5 check, capped status polling, and `dfuERROR` treated as failure.
- Generated firmware must keep the Navigator modules working.

## ZSA material

Sextant is not affiliated with ZSA. Don't add ZSA logos, artwork, screenshots, Oryx colors or text copied from Oryx, and don't commit other people's Oryx layouts. Say "ZSA Voyager" in text only.

## Test fixtures

`docs/research/oryx-examples/` holds the author's own Oryx layout and its Oryx-generated QMK source, which the golden tests always use. A few more public Oryx samples are kept outside the repo. Tests that need them read the folder named by the `SEXTANT_REFERENCE` environment variable (same relative paths) and are skipped without it, so a fresh clone passes.

## Snapshot tests

Pixel snapshot references (`Tests/SextantUITests/__Snapshots__`) are rendered on the maintainer's macOS and are skipped on CI (`CI` is set). If you change what they show, re-record them locally and look at every image before committing. UI checks render offscreen (`swift run SextantSnapshots <dir>`); never use screen capture.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
