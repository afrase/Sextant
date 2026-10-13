# Sextant

Sextant is a native macOS 26 SwiftUI app for configuring the user's ZSA Voyager. It edits layouts locally, imports from Oryx, builds QMK firmware, flashes it, and shows the keyboard live. It is not affiliated with ZSA.

## Start here

- `docs/design/ui-spec.md`: what to build. §13 covers targets, APIs and the MVP build order. §14 lists the taste calls, all decided.
- `docs/research/00-overview.md`: how Oryx, the firmware, the flasher and live HID work, plus the architecture and its risks. Section 4 covers flasher safety.
- `docs/decisions.md`: settled decisions, plus what is still open. From decision 6 on, each has an ADR in `docs/adr/`; add one for every significant choice.
- `docs/architecture.md`: the code design (targets, ports, adapters, concurrency, errors, `.sextant` format, testing).
- `docs/progress.md`: what is done, what comes next, what is blocked. Read it first after a context reset.

**Status:** the MVP is done and v1 is under way (`docs/progress.md`, `docs/v1-plan.md`). Run `scripts/check` before every commit.

## Architecture: clean / hexagonal (decision 5)

**The rule:** dependencies point inward only.
- **Domain:** pure Swift and Foundation only. It holds the layout, layers, keys and actions, the keycode catalog, geometry, legends, validation and diffing. No SwiftUI, AppKit, IOKit, URLSession or file I/O.
- **Application (use cases):** orchestrates the domain. Editing with undo, Import, Build & Flash and the live session live here. It reaches the outside world only through **ports**, which are protocols defined in this layer. Examples: layout library, Oryx reader, firmware generator, toolchain, flasher, keyboard link, device watcher, clock.
- **Adapters:** implement the ports. Examples: `.sextant` package storage, Oryx GraphQL over URLSession, the QMK generator and toolchain backends, the IOUSBHost DFU flasher, and IOHID/CoreHID raw HID. Each adapter depends on the application layer, never the reverse.
- **UI:** a driving adapter. SwiftUI views plus `@Observable` view models that call use cases. Views never touch adapters directly.
- **Composition root:** the app target, the only place that wires concrete adapters to ports.

**Enforce it with module boundaries,** one SwiftPM target per layer or adapter group, so a wrong import fails to compile. `docs/architecture.md` §1 lists the targets and reconciles them with spec §13.1.

**Testing follows the layers:**
- domain and use cases: unit tests with in-memory fakes of the ports;
- adapters: contract tests;
- the generator: golden tests against the user's layout in `docs/research/oryx-examples/` and, with `SEXTANT_REFERENCE` set, the other Oryx samples in the reference folder.

## Swift and macOS practices

- **Language and concurrency:** Swift 6 language mode with complete strict concurrency.
  - Domain types are `Sendable` value types (structs and enums).
  - Device I/O lives in actors.
  - UI state is `@MainActor`.
  - Use async/await and `AsyncStream` for device events, with structured concurrency and cancellation.
- **Design:** inject dependencies through initializers. No singletons and no global mutable state.
- **Errors:** typed errors, with `LocalizedError` for anything the user sees. No `try!` or force-unwraps outside tests.
- **SwiftUI:** use Observation (`@Observable`), not `ObservableObject`. Use the native scenes and controls the spec names: `NavigationSplitView`, `.inspector`, `Commands`, `Settings`, `MenuBarExtra`. Undo goes through `UndoManager`.
- **Tests:** Swift Testing (`import Testing`, `@Test`, `#expect`).
- **Logging:** `os.Logger`, with subsystem `com.sextant.app` and a category per layer.
- **Strings and accessibility:** String Catalogs for user-facing text, plus accessibility labels and VoiceOver on custom views, especially the board.
- **Packaging:** a real `.app` bundle with hardened runtime and minimal entitlements, Developer ID signed and notarized (00-overview §8). All code lives in the local Swift package; the app target stays a thin shell.
- **Formatting:** `swift format`, which ships with the toolchain.
- **CI's compiler is older:** GitHub's macos-26 runner builds with Xcode 26.6 (Swift 6.3, macOS 26.5 SDK). Things that pass locally on Swift 6.4 but break there: a typed pattern catch in a loop (`catch .notFound where …` crashed the compiler), more than ten children in a `Commands` body (wrap some in `Group`), a method reference passed as a `Binding` setter (use a closure), and implicit `(Int, CGFloat)` to `(Int, Double)` conversions.

## Code

- **Toolchain:** SwiftPM, Swift 6, macOS 26. Prefer established community libraries and tools over writing our own (ADR 0018): pin them exactly, permissive licenses only, and ask before adding new ones (downloads).
- **Module names:** never name a module exactly `Sextant`. Prefix every target with `Sextant`.
- **`design/` is reference, not production code:**
  - `design/PrototypeKit` (model, legends, keycodes, geometry, samples) seeded `SextantDomain`. Port from it; don't depend on it.
  - The early prototypes and their judging (`design/explorations/`, `design/judging/`) live in the reference folder, not the repo.
- **Tests:** `docs/research/oryx-examples/` holds the user's own Oryx JSON and its generated QMK source, for golden tests. Other people's samples are in `~/Developer/Sextant-reference/`; tests read `SEXTANT_REFERENCE` (which `scripts/check` sets) and skip without it.
- **No TCC prompts in automated runs.** Don't use screencapture or ScreenCaptureKit. Render UI offscreen, the way PrototypeKit's `SnapshotRunner` does.

## Hardware safety (non-negotiable)

- Never send anything to the keyboard without the user's explicit OK in chat, given for that action. This covers raw HID writes, RGB takeover, entering the bootloader and DFU. Read-only enumeration is fine. The rule binds agents building and testing Sextant; in the shipped app the user's own Build & Flash click is the consent for flashing (ADR 0056).
- **Flasher guards:**
  - only write within `[0x08002000, 0x08042000)`, and never MASS_ERASE;
  - the DFU suffix VID, PID and CRC must match the connected bootloader (`3297:0791` STM32 or `3297:1791` GD32);
  - md5-verify the image;
  - cap status polling, and treat `dfuERROR` as failure.
- Generated firmware must keep the Navigator trackpad (ZSA's modules) working.

## External services and repo

- **Oryx:** reads only, through its public GraphQL. No logins and no mutations.
- **Branding:** no ZSA trade dress (logos, Voyager art, Oryx colors). Use "ZSA Voyager" in text only.
- **Git:** the repo is public at github.com/afrase/Sextant (MIT). Commit when the user asks, and never push without the user's OK. ZSA-derived material and other people's layouts live in `~/Developer/Sextant-reference`, never in the repo; tests read `SEXTANT_REFERENCE` (ADR 0055).
