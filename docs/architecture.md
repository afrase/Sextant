# Sextant code architecture

Status: v1 of the code design, 2026-10-11. It implements decision 5 (clean / hexagonal) and reconciles ui-spec §13.1 with it. Every significant choice is indexed in `docs/decisions.md` and recorded as an ADR in `docs/adr/`.

## 1. Shape

One SwiftPM package at the repo root (`Package.swift`). One target per layer or adapter group, so a wrong import fails to compile. The app executable is the composition root and stays thin.

```
                         ┌──────────────────────┐
                         │ SextantApp (exe)     │  composition root: wires adapters → ports,
                         │                      │  scenes, --import flag
                         └──────────┬───────────┘
        ┌───────────────┬───────────┼────────────┬──────────────┬──────────────┐
        ▼               ▼           ▼            ▼              ▼              ▼
 SextantStorage   SextantOryx   SextantBuild  SextantDevice  SextantUI   SextantSnapshots
 (.sextant pkgs)  (GraphQL)     (generator,   (IOKit HID,    (SwiftUI,    (dev-tool exe:
                                 toolchains)   IOUSBHost DFU, view models) offscreen scenes)
                                               device watch)
        │               │           │            │              │
        └───────────────┴─────┬─────┴────────────┴──────────────┘
                              ▼
                     SextantApplication   use cases + ports (protocols)
                              │
                              ▼
                       SextantDomain      pure Swift + Foundation
```

Arrows are `dependencies:` in `Package.swift`. Nothing depends on `SextantApp`. Adapters never depend on each other, or on `SextantUI`. `SextantSnapshots` is a dev-tool executable (the ported offscreen renderer plus the scene list); the app binary carries no snapshot code.

| Target | Layer | May import | Contents |
|---|---|---|---|
| `SextantDomain` | domain | Foundation (+ CoreGraphics value types) | Layout model, Oryx JSON codec, keycode catalog, legends, Voyager board definition and geometry, settings catalog, validation (live issues), diffing, firmware image validation, colour maths |
| `SextantApplication` | use cases | `SextantDomain`, Foundation, Observation, os | Ports (protocols), use cases (`EditSession`, `Library`, `ImportFromOryx`, `LiveSession`, `OnKeyboard`, `BuildFlashSession`), typed errors |
| `SextantStorage` | adapter | Application, Domain, Foundation, CryptoKit | `PackageLibrary`: the `.sextant` library in Application Support |
| `SextantOryx` | adapter | Application, Domain, Foundation (URLSession), CryptoKit | `OryxClient`: read-only GraphQL `layout` query, firmware download with md5 check |
| `SextantBuild` | adapter | Application, Domain, Foundation | `QMKGenerator` (Oryx-equivalent source + source map), `NativeToolchain` with its pinned `ToolchainInstaller` and `sandbox-exec` profile, compiler-diagnostic parser, size parser |
| `SextantDevice` | adapter | Application, Domain, IOKit, IOUSBHost, CryptoKit, Carbon (secure input) | `IOKitDeviceWatcher`, `RawHIDLink` (Oryx protocol v5), `DFUFlasher` (DfuSe with guards), `SecureInputProbe` |
| `SextantUI` | driving adapter | Application, Domain, SwiftUI, AppKit | Views, `@Observable` view models, tokens, `SurfaceStyle`, `SextantMotion`, board, commands |
| `SextantSnapshots` | dev-tool executable | UI, Application, Storage, SwiftUI, AppKit | Ported PrototypeKit snapshot runner (offscreen, no TCC) and the design-QA scene list |
| `SextantApp` | composition root | everything | `@main`, adapter wiring, scenes |

Test targets mirror them: `SextantDomainTests`, `SextantApplicationTests`, `SextantStorageTests`, `SextantOryxTests`, `SextantBuildTests`, `SextantDeviceTests`, `SextantUITests`.

### 1.1 Reconciling spec §13.1

| §13.1 target | Becomes | Why |
|---|---|---|
| `SextantKit` (model, Oryx import/export, geometry, legends, catalogs, `EditorStore`) | `SextantDomain` (model, codec, geometry, legends, catalogs) + `SextantApplication` (`EditSession`, the old `EditorStore`) + `SextantOryx` (network half of import) + `SextantStorage` | Undo and I/O are not domain. Network and files are adapters. |
| `SextantBoard` (KeyCap, BoardView, lenses, a11y) | folder `SextantUI/Board` | It is UI-layer code with the same dependencies as the rest of the UI. A separate target buys nothing the layer rule needs. |
| `SextantDevice` | `SextantDevice` (I/O only) + `LiveSession` in Application | The live state machine is a use case; the adapter only speaks HID and USB. |
| `SextantBuild` | `SextantBuild` (generator + toolchains) + `BuildFlashSession` in Application | Same split: orchestration is a use case. |
| `SextantApp` | `SextantUI` (all views) + `SextantApp` (composition root only) | The app target stays a thin shell (CLAUDE.md). |

## 2. Domain (`SextantDomain`)

All types are `Sendable` value types. No SwiftUI, AppKit, IOKit, URLSession or file I/O. Geometry imports CoreGraphics for its value types only (ADR 0008).

### 2.1 Layout model (ported from PrototypeKit `Model/`)

- `KeyboardLayout`: the document content. `title`, `geometry` ("voyager", which names its `BoardDefinition`), `layers: [Layer]`, `combos: [Combo]`, `settings: [String: SettingValue]` (sparse, Oryx convention), `navigator: NavigatorConfig?`, `swatch: [HexColor]`, plus `oryx: OryxRevisionInfo?` (layout id, revision id, firmware version, md5, createdAt, message) when it came from Oryx. The generator assumes firmware 25 when `oryx?.firmwareVersion` is missing. Operations: key lookup and update, transparent resolution (`resolvedKey`), `keysActivating(layer:)`, `moveLayer` / `removeLayer` with reference remapping, `diff(from:)`.
- `Layer` (stable `id`: Oryx hashId or UUID, `title`, `color`, one key per board key: 52 on the Voyager), `Key` (tap / hold / doubleTap / tapHold, `customLabel`, `glowColor`, `tappingTerm`), `KeyAction` (code, layer, modifiers, macro, color, description), `KeySlot`, `KeyKind`, `Modifiers`, `Macro`, `MacroStep`, `Combo`, `NavigatorConfig`, `HexColor` (no `.color` / `.nsColor`; those are UI extensions), `SettingValue`.
- **Codec.** `KeyboardLayout: Codable` writes and reads **Oryx's revision JSON shape** (keys with `tap.code`, `modifiers` as 8 booleans, layers with `hashId`/`title`/`color`/`keys`, sparse `config`, `navigators`, `combos`, `swatch`). `KeyboardLayout(oryxJSON:)` also accepts the GraphQL envelope `{"data":{"layout":…}}`. One codec serves import, storage and export. Nil fields are omitted on write; Oryx's leaked UI-state fields and display-only fields (`icon`, `emoji`, `about*`, `tour`) are dropped on read (ADR 0007).

### 2.2 Catalogs and board data

- `KeycodeCatalog` / `KeycodeEntry` / `KeycodeCategory`: Sextant's own labels and names for ~320 codes, aliases, ranked search (ported as-is).
- `SettingsCatalog` / `Setting` / `SettingsSection`: 14 sections, 100 settings with Oryx ids, defaults and ranges and Sextant's text. Embedded as a JSON string literal and decoded once, so the domain needs no resource bundle.
- `BoardDefinition` (ADR 0017): `BoardDefinition.all` lists the boards Sextant knows and `named(_:)` finds a layout's board by its `geometry`. Today that is `.voyager`: per key the Oryx index, matrix row/column, LED index, hand, cluster, row/column, Oryx stagger and home-row flag, as a Swift table generated once from `docs/research/data/voyager-matrix-led-map.json` and `voyager-geometry.json`. Also USB ids (`3297:1977|1978`, bootloaders `0791`/`1791`) and the flash window. Nothing else hard-codes 52, the PIDs or addresses (00 §8).
- `BoardGeometry` / `BoardLayout`: key-unit geometry, point layout, rotation-aware hit test, `neighbor(of:toward:)`. `BoardDefinition.geometry(navigator:)` builds a board's shapes; the UI sizes the board from them, never from Voyager constants.

### 2.3 Derived views of a layout

- `Legends` → `KeyLegend`, `ActionLegend`, `ResolvedLegend` (ported). Pure text and SF Symbol names.
- `LayoutIssues.check(_:)` → `[LayoutIssue]` (unknown keycode, missing layer, unreachable layer, macro too long, empty combo, tap dance before generator support, near size limit). Each issue carries a `KeyRef` (layer, index, slot) so the UI can badge the cap.
- `OryxReference(string)`: parses `configure.zsa.io` URLs, `layout/revision` serials and bare ids.
- `ImportSummary(layout)`: layers, assigned keys, dual-function keys, labels, colour keys, macros.
- `FlashPath`: the `QK_BOOT` key and the chain of holds from layer 0 that reaches it (Build & Flash card B).
- `ColorContrast`: WCAG luminance and contrast, `adjusted(toContrast:against:)` for `layer.display` and `layer.ink` (§4.5).

### 2.4 Firmware image

`FirmwareImage(data:)` parses a `.bin` with a DFU suffix. `validate(forBootloaderPID:)` enforces, as hard failures with a typed `FirmwareImageError`:
- the last 16 bytes are a DFU suffix with `UFD` signature and length 16;
- the suffix CRC matches (CRC-32 reflected, init `0xFFFFFFFF`, no final XOR);
- suffix VID is `0x3297` and suffix PID equals the connected bootloader PID; a single image on `0x1791` is refused;
- payload length ≤ the flash window (`0x08042000 − 0x08002000`);
- vector table sanity: initial MSP in `[0x20000000, 0x20008000]`, reset vector odd and inside `[0x08002000, 0x08020000)`.

md5 needs CryptoKit, so md5 checks live in the adapters that download (`SextantOryx`) and flash (`SextantDevice`).

## 3. Application (`SextantApplication`)

### 3.1 Ports

All ports are `Sendable` protocols with `async` methods and **typed throws**. Implementations are actors or `Sendable` structs.

| Port | Methods (shape) | Adapter | Fake (tests) |
|---|---|---|---|
| `LayoutLibrary` | `entries()`, `load(id)` (with the working copy's content hash), `create`, `save`, `appendRevision`, `layout(ofRevision:in:)`, `rename`, `duplicate`, `trash`, `storeFirmware` / `firmware(revisionID:of:)`, `location(of:)` | `PackageLibrary` (SextantStorage) | `InMemoryLibrary` |
| `OryxReader` | `layout(ref) -> KeyboardLayout`, `firmware(revisionID, expectedMD5) -> Data` | `OryxClient` (SextantOryx) | `FakeOryx` |
| `FirmwareGenerator` | `generate(layout, identity) throws -> GeneratedSource` (files + source map) | `QMKGenerator` (SextantBuild) | `FakeGenerator` |
| `Toolchain` | `status()`, `build(source, board) -> AsyncStream<BuildEvent>` (output, progress, then `.finished(BuildArtifact)` or `.failed(ToolchainError)`), `setUp() -> AsyncStream<SetupEvent>` (the consented one-time download) | `NativeToolchain` (SextantBuild) | `FakeToolchain` |
| `DeviceWatcher` | `events(for: board) -> AsyncStream<DeviceEvent>` (`.attached(ConnectedDevice)`, `.detached(id)`) | `IOKitDeviceWatcher` | `FakeDeviceWatcher` |
| `KeyboardLink` | `session(with: device, board:) -> AsyncStream<LiveEvent>` (serial, protocol version, layer, key down/up by matrix position, then `.ended`) | `RawHIDLink`, or `RefusingKeyboardLink` behind the gate | `FakeKeyboardLink` |
| `Flasher` | `flash(image, md5:, to: BootloaderDevice, board:, progress:)` | `DFUFlasher` (SextantDevice), or `RefusingFlasher` behind the gate | `FakeFlasher` |

Small things that are not worth a port are injected as values: an `any Clock<Duration>` for debounce and timeouts, a `@Sendable () -> Bool` secure-input probe, an `UndoManager`.

### 3.2 Use cases

| Use case | Isolation | Does |
|---|---|---|
| `Library` | `@MainActor @Observable` | Lists library entries; opens, creates (blank QWERTY), duplicates, renames, trashes layouts. One document per layout (`isOpen`, `close`), so one window per layout; writes pending autosaves on close and quit |
| `EditSession` | `@MainActor @Observable` | One open document: `layout`, `selection` (layer, key, slot), every undoable edit from PrototypeKit's `EditorStore` (set action / code / modifiers / label / colour, paint, transparent, disable, swap, override, layer add / duplicate / rename / colour / move / delete, settings, title). Registers undo on the window's `UndoManager` with named actions and snapshots layout + selection. Debounced autosave (1 s) through `LayoutLibrary`, plus an immediate recovery copy of every change until its autosave lands (ADR 0032). Live issues recomputed per edit. |
| `ImportFromOryx` | `@MainActor @Observable` | Steps: read link → fetch layout → fetch Oryx's firmware with md5 (optional) → convert; an `ImportSummary` preview; saves as a new layout or as a revision of an existing one with the same Oryx id, checkpointing local edits first (ADR 0024). Strips " [fork]". |
| `LiveSession` | `@MainActor @Observable` | Consumes `DeviceWatcher` and `KeyboardLink`. State: connection (none / connected / bootloader / held by another app / access off), serial and `FirmwareMatch` (ADR 0019), active layer, pressed key indices (matrix → index via `BoardDefinition`), Follow mode, secure-input pause. Coalesces to ≤ 60 Hz, reconnects with backoff, never stores or logs events (ADR 0023). |
| `OnKeyboard` | `@MainActor @Observable` | App-wide: which library entry, revision and layout the keyboard runs, from `LiveSession`'s serial alone (works with live access off). An Oryx serial names its import revision; a Sextant serial names the working copy when the fingerprint matches, else the newest matching flash revision; never unflashed edits (ADR 0039). Re-resolves on serial change, library refresh and the end of a flash. |
| `BuildFlashSession` | `@MainActor @Observable` | The §7 state machine: issues gate → generate → compile (progress, log mapped through the source map) → size → wait for bootloader → validate image → flash → wait for re-enumeration and serial check → record a revision, then release flash mode (`OnKeyboard` relies on that order, ADR 0039). Cancel is refused during erase / write / verify. |

### 3.3 Hardware gate

Raw-HID writes (pairing, protocol query) and flashing need the user's explicit hardware approval (CLAUDE.md). Until it is given, the composition root wires `KeyboardLink` and `Flasher` to refusing implementations, and the real adapters are reachable only when their user defaults are set by hand: `SextantFlashingEnabled` (the flasher) and `SextantLiveAccessEnabled` (the raw-HID link), or `SextantHardwareEnabled` for both. Read-only enumeration (`IOKitDeviceWatcher`) is always on. See ADRs 0012 and 0034.

## 4. Adapters

- **`SextantStorage.PackageLibrary`** (actor): §6 format; atomic writes (`Data.write(options: .atomic)`); SHA-256 content hash of the canonical JSON; per-revision Oryx firmware; trash via `FileManager.trashItem`.
- **`SextantOryx.OryxClient`** (struct over an injected `URLSession`): `POST https://oryx.zsa.io/graphql` with the `getLayout` query and a descriptive User-Agent; `GET /firmware/{rev}` with md5 enforced. Never logs in, never mutates. Contract tests use a `URLProtocol` stub with fixture JSON from `docs/research/oryx-examples/`.
- **`SextantBuild.QMKGenerator`** (struct, pure): emits `keymap.c`, `config.h`, `rules.mk`, `keymap.json` (and `i18n.h` when needed) following research 02 §4, keeping `zsa/oryx`, `zsa/defaults` and the Navigator modules. Emits a source map (keymap.c line → `KeyRef`). Settings follow Oryx's output where its samples show it and Sextant's own mapping where they don't (ADR 0040); a setting with neither stops the build by name (ADR 0020).
- **`SextantBuild` toolchain** (ADR 0033): `NativeToolchain` runs `qmk compile` on the Mac with Arm's GCC 12.2.1 (ZSA's release), GNU make 4 and Python with the `qmk` CLI, against ZSA's fork at pinned commits, all in `~/Library/Caches/com.sextant.app/Toolchain` (QMK can't take spaces in paths). Every build runs under `sandbox-exec`: no network, no reads in the home folder outside the toolchain, writes only to the build folder and its image. `ToolchainInstaller` (one actor, shared by every window) fills the folder only from the setup step, with consent: each artifact pinned by URL, size and SHA-256 (`ToolchainPins`), pruned while unpacking, wheels installed by pip from the verified files only, and a marker written last. Sextant appends the DFU suffix itself (`FirmwareImage.withSuffix`). Output streams through the shared `file:line:col: error:` diagnostic and size parsers.
- **`SextantDevice.IOKitDeviceWatcher`** (actor): `IOServiceAddMatchingNotification` for VID `0x3297`, PIDs from `BoardDefinition`; reads serial and `bcdDevice`. Read-only.
- **`SextantDevice.RawHIDLink`** (actor on its own serial dispatch queue): IOHIDManager matching usage page `0xFF60` / usage `0x61` only, opened non-exclusively, 32-byte reports. Oryx protocol v5 parsing lives behind an internal `HIDTransport` protocol so it is tested with a fake transport.
- **`SextantDevice.DFUFlasher`** (actor on its own serial queue): DFU 1.1 + DfuSe over an internal `USBControlTransport` protocol, implemented with `IOUSBHostInterface.sendDeviceRequest`. Guards, all unit-tested against a fake DfuSe device: address window `[0x08002000, 0x08042000)` on every erase and write, never MASS_ERASE, image re-validated for the connected PID, md5 check, GETSTATUS polls capped (count and total time), `dfuERROR` is failure, CLRSTATUS once at start only.
- **`SextantUI`**: views and `@Observable` view models. View models call use cases only; they never see adapters. One `LayoutWindowModel` per window owns the open `EditSession` and that layout's `BuildFlashSession`; `LiveSession` is shared. Folders follow the window's regions (`Sidebar`, `Canvas`, `Board`, `Inspector`, `Picker`, `Lighting`, `Import`, `FirmwareSettings`, `Settings`, `Device`, `BuildFlash`, `Commands`, `Window`, `Theme`). Window-wide state reaches deep views through the environment (`brush`, `swapsKeys`, `layoutWindow`) rather than new view parameters; sheets and alerts hang off one `windowPresentations` modifier. A board gesture must be gated on the lens (ADR 0029).

### 4.1 Composition root (`SextantApp`)

`@main struct SextantMain` builds the concrete adapters (the raw-HID link and the flasher only when their defaults are set, ADRs 0012 and 0034), starts `LiveSession` and `OnKeyboard`, and hands `SextantUI` a `SextantServices` value: `Library`, `LiveSession`, `OnKeyboard`, and factories for `ImportFromOryx` and `BuildFlashSession`. The UI never sees an adapter. Command-line flag: `--import <oryx.json>` imports a layout file into the library at launch. Snapshots are a separate tool: `swift run SextantSnapshots <dir> [--only a,b]`. No singletons: everything flows from `SextantMain`.

## 5. Concurrency

- Swift 6 language mode, complete strict concurrency, in every target.
- Domain: nonisolated `Sendable` values.
- Use cases that hold UI-facing state: `@MainActor @Observable`. Their ports are awaited off the main actor.
- Device I/O: actors whose executor is a dedicated `DispatchSerialQueue`, so IOKit callbacks scheduled on that queue run actor-isolated. DFU control transfers are synchronous on that queue, with timeouts.
- Device and build events: `AsyncStream` / `AsyncThrowingStream`, consumed in tasks owned by the use case and cancelled when it goes away (structured concurrency; `withTaskCancellationHandler` closes devices).
- Live presses are coalesced to ≤ 60 Hz before touching `@MainActor` state; pressed state is keyed per index so a press does not invalidate every cap.

## 6. The `.sextant` package

Library root: `~/Library/Application Support/Sextant/Library/`. One folder per layout:

```
My MacOS Layout-1F3A9C.sextant/
  meta.json                 {"formatVersion":1,"id":"<UUID>","title":…,"origin":{"kind":"oryx","layoutId":"KlgM7","revisionId":"40xJ7M"},
                             "createdAt":…,"modifiedAt":…,"contentHash":"sha256:…"}
  layout.json               the working copy: KeyboardLayout in Oryx revision shape, pretty-printed, sorted keys
  revisions/
    0001-3b9f2c1e.json      {"id":…,"number":1,"parent":null,"createdAt":…,"source":"import|flash|save",
                             "message":…,"contentHash":"sha256:…","layout":{…}}   append-only, never rewritten
  firmware/
    <revisionId>.bin        an Oryx- or Sextant-built image
    <revisionId>.bin.md5
.recovery/<UUID>.json       the latest edits until their autosave lands (ADR 0032)
```

- Folder names are for humans; identity is `meta.json` `id`. Renaming a layout rewrites `meta.json` and renames the folder.
- `contentHash` is SHA-256 over the canonical (sorted-keys) JSON of `layout`, written as `sha256:<hex>`. It powers "Edited since revision", "Flash Oryx's build" (hash equals an imported revision) and future sync.
- `formatVersion` greater than the build's is refused with a typed error, never misread.

## 7. Errors

- Each port has a typed error enum in the application layer (`LibraryError`, `OryxError`, `BuildError`, `ToolchainError`, `DeviceError`, `FlashError`); domain has `FirmwareImageError`, `OryxDecodingError`, `LayoutError`. Ports and use cases use typed throws (`throws(OryxError)`); adapters map platform errors at the boundary.
- Anything the user sees conforms to `LocalizedError` with the spec's copy (§8.1 table, §12.6 catalog): sentence case, what happened, what it means, what to do.
- No `try!`, `fatalError` or force-unwrap outside tests, except for compile-time-constant data proven by a test (the embedded catalogs).
- Logging: `os.Logger(subsystem: "com.sextant.app", category: <layer>)` with categories `domain`, `application`, `storage`, `oryx`, `build`, `device`, `ui`, `app`. Key events and typed text are never logged.

## 8. Testing

| Layer | Kind | Where |
|---|---|---|
| Domain | unit (Swift Testing) | model, codec round-trip on all 7 Oryx JSON files, legends, catalog search, geometry, issues, diff, image validation, contrast thresholds for the 2 user colours and 10 swatches |
| Application | unit with in-memory fakes of every port | undo/redo with named actions, autosave debounce, import flow, live session state, build/flash state machine including refusal paths |
| Storage | contract (temp directory) | create / load / save / revisions / rename / trash / formatVersion refusal |
| Oryx | contract (`URLProtocol` stub) | request shape (query, no auth header, User-Agent), envelope decode, not-found / offline / other-board errors, md5 mismatch |
| Build | golden | generate from the 5 Oryx JSON files and diff against the unzipped `docs/research/oryx-examples/sources/*.zip`, normalising whitespace and DUAL_FUNC placeholder numbering; diagnostics and size parsers |
| Device | unit with fake transports | DFU guards and algorithm against a fake DfuSe device; Oryx HID protocol parsing; matrix → index |
| UI | view-model unit tests; offscreen snapshots via `swift run SextantSnapshots <dir>` | snapshots are looked at, not diffed |

`scripts/check` (ADR 0018): swift-format lint (`.swift-format`; force unwraps and force tries banned in Sources), SwiftLint (`.swiftlint.yml`: quality rules plus path-scoped layer import rules), a warnings-as-errors build, `swift test`, and a Periphery unused-code report (`.periphery.yml`). `scripts/strings` syncs the String Catalog (ADR 0016).

## 9. Building the app bundle

SwiftPM plus `scripts/bundle`, no Xcode project (ADR 0011). The script builds `SextantApp` in release, assembles `Sextant.app/Contents/{MacOS/Sextant, Info.plist, Resources/*.bundle}` from `Resources/Info.plist`, compiles `Resources/Localizable.xcstrings` into it, and signs with the hardened runtime and `Sextant.entitlements` using `SEXTANT_SIGN_IDENTITY` (ad-hoc `-` when unset), entitlements from `Resources/Sextant.entitlements`. `scripts/notarize` wraps `xcrun notarytool submit --wait` and `stapler`; it needs the user's credentials and is never run automatically. SwiftPM's resource accessor finds bundles in `Contents/Resources`, and `swift build` compiles String Catalogs and asset catalogs, so nothing needs Xcode's build system.

## 10. Porting PrototypeKit

PrototypeKit is the seed, not a dependency.

| PrototypeKit | Destination | Changes |
|---|---|---|
| `Model/*` | `SextantDomain/Model` | `OryxDecoding` folded into Codable; `HexColor` loses SwiftUI/AppKit; `swatch` and `oryx` info added |
| `Legends/*` | `SextantDomain/Legends` | as-is, plus `swift format` |
| `Settings/SettingsCatalog` + JSON | `SextantDomain/Settings` | JSON embedded as a literal |
| `Geometry/BoardGeometry` | `SextantDomain/Geometry` | reads `BoardDefinition` instead of the bundled research JSON |
| `Geometry/BoardCanvas` | `SextantUI/Board` | as-is |
| `Editor/EditorStore` | `SextantApplication/EditSession` | autosave, issues, injected `UndoManager`, override-key edit |
| `Samples/*` | not ported | replaced by real adapters and test fakes; `OryxLayoutReference` → domain `OryxReference`, import summary → `ImportSummary`, `BuildFlashPhase` → `BuildFlashSession.Phase` |
| `Snapshot/*` | `SextantSnapshots` | renamed; `isSnapshot` moved to `SextantUI` |
