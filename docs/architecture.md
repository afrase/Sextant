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
| `SextantApplication` | use cases | `SextantDomain`, Foundation, Observation, os | Ports (protocols), use cases (`EditSession`, `Library`, `ImportFromOryx`, `LiveSession`, `OnKeyboard`, `LightingPreview`, `HeatmapRecorder`, `AppLayerSwitcher`, `BuildFlashSession`), typed errors |
| `SextantStorage` | adapter | Application, Domain, Foundation, CryptoKit | `PackageLibrary`: the `.sextant` library in Application Support; `HeatmapFiles`: the Heatmap's hourly counts beside it (ADR 0053) |
| `SextantOryx` | adapter | Application, Domain, Foundation (URLSession), CryptoKit | `OryxClient`: read-only GraphQL `layout` query, firmware download with md5 check |
| `SextantBuild` | adapter | Application, Domain, Foundation | `QMKGenerator` (Oryx-equivalent source + source map), `NativeToolchain` with its pinned `ToolchainInstaller` and `sandbox-exec` profile, compiler-diagnostic parser, size parser |
| `SextantDevice` | adapter | Application, Domain, IOKit, IOUSBHost, CryptoKit, Carbon (secure input) | `IOKitDeviceWatcher`, `RawHIDLink` (Oryx protocol v5), `DFUFlasher` (DfuSe with guards), `SecureInputProbe` |
| `SextantUI` | driving adapter | Application, Domain, SwiftUI, AppKit, PDFKit (printing) | Views, `@Observable` view models, tokens, `SurfaceStyle`, `SextantMotion`, board, commands, exports and printing |
| `SextantSnapshots` | dev-tool executable | UI, Application, Storage, SwiftUI, AppKit | Ported PrototypeKit snapshot runner (offscreen, no TCC) and the design-QA scene list |
| `SextantApp` | composition root | everything, plus KeyboardShortcuts | `@main`, adapter wiring, scenes; `KeyboardShortcutsHotKeys`, the global layer shortcuts' adapter and recorder (ADR 0048); `WorkspaceAppWatcher`, App Layers' frontmost-app adapter over NSWorkspace (ADR 0054) |

Test targets mirror them: `SextantDomainTests`, `SextantApplicationTests`, `SextantStorageTests`, `SextantOryxTests`, `SextantBuildTests`, `SextantDeviceTests`, `SextantUITests`.

### 1.1 Reconciling spec §13.1

| §13.1 target | Becomes | Why |
|---|---|---|
| `SextantKit` (model, Oryx import/export, geometry, legends, catalogs, `EditorStore`) | `SextantDomain` (model, codec, geometry, legends, catalogs) + `SextantApplication` (`EditSession`, the old `EditorStore`) + `SextantOryx` (network half of import) + `SextantStorage` | Undo and I/O are not domain. Network and files are adapters. |
| `SextantBoard` (KeyCap, BoardView, lenses, a11y) | folder `SextantUI/Board` | It is UI-layer code with the same dependencies as the rest of the UI. A separate target buys nothing the layer rule needs. |
| `SextantDevice` | `SextantDevice` (I/O only) + `LiveSession` in Application | The live state machine is a use case; the adapter only speaks HID and USB. |
| `SextantBuild` | `SextantBuild` (generator + toolchains) + `BuildFlashSession` in Application | Same split: orchestration is a use case. |
| `SextantApp` | `SextantUI` (all views) + `SextantApp` (composition root only) | The app target stays a thin shell (AGENTS.md). |

## 2. Domain (`SextantDomain`)

All types are `Sendable` value types. No SwiftUI, AppKit, IOKit, URLSession or file I/O. Geometry imports CoreGraphics for its value types only (ADR 0008).

### 2.1 Layout model (ported from PrototypeKit `Model/`)

- `KeyboardLayout`: the document content. `title`, `geometry` ("voyager", which names its `BoardDefinition`), `layers: [Layer]`, `combos: [Combo]`, `settings: [String: SettingValue]` (sparse, Oryx convention), `navigator: NavigatorConfig?`, `swatch: [HexColor]`, `macroDrafts: [MacroDraft]` (macros on no key yet, Sextant's own), plus `oryx: OryxRevisionInfo?` (layout id, revision id, firmware version, md5, createdAt, message) when it came from Oryx. The generator assumes firmware 25 when `oryx?.firmwareVersion` is missing. Operations: key lookup and update, transparent resolution (`resolvedKey`), `keysActivating(layer:)`, `moveLayer` / `removeLayer` with reference remapping, `diff(from:)`, the macro library (`macros` by `MacroLocator`: key slot, combo or draft; assign, unassign, remove, step edits, `MacroStep.canType`; ADR 0042), and combo edits (`Layout+Combos`: add, remove, toggle a key, set keys, output, layer and name; `Combo.keysLayer`, the layer whose keycodes a combo matches; ADR 0046).
- `Layer` (stable `id`: Oryx hashId or UUID, kept through Oryx revisions by `keepingLayerIDs(of:)` along Oryx's `prevHashId`, with Oryx's current hash id in `oryxID` when it differs (ADR 0054); `title`, `color`, one key per board key: 52 on the Voyager), `Key` (tap / hold / doubleTap / tapHold, `customLabel`, `glowColor`, `tappingTerm`), `KeyAction` (code, layer, modifiers, macro, color, description), `KeySlot`, `KeyKind`, `Modifiers`, `Macro`, `MacroStep`, `Combo`, `NavigatorConfig`, `HexColor` (no `.color` / `.nsColor`; those are UI extensions), `SettingValue`.
- Feature operations live in `Layout+<Feature>.swift`:
  - `Layout+TappingTerm`: `setTappingTerm` (bounded, nil at the global term, shared by keys with the same actions; ADR 0041).
- **Codec.** `KeyboardLayout: Codable` writes and reads **Oryx's revision JSON shape** (keys with `tap.code`, `modifiers` as 8 booleans, layers with `hashId`/`title`/`color`/`keys`, plus Sextant's `oryxHashId` when present (Oryx's `prevHashId` is read, never written), sparse `config`, `navigators`, `combos`, `swatch`). `KeyboardLayout(oryxJSON:)` also accepts the GraphQL envelope `{"data":{"layout":…}}`. One codec serves import, storage and export. Nil fields are omitted on write; Oryx's leaked UI-state fields and display-only fields (`icon`, `emoji`, `about*`, `tour`) are dropped on read (ADR 0007).

### 2.2 Catalogs and board data

- `KeycodeCatalog` / `KeycodeEntry` / `KeycodeCategory`: Sextant's own labels and names for ~320 codes, aliases, ranked search (ported as-is).
- `SettingsCatalog` / `Setting` / `SettingsSection`: 14 sections, 101 settings with Oryx ids, defaults and ranges and Sextant's text and search synonyms. Embedded as a JSON string literal and decoded once, so the domain needs no resource bundle. `offers(_:)` says which settings Sextant shows and counts (60 for the Voyager; hidden ones keep imported values), and `KeyboardLayout.store` applies Oryx's coupling rules, so a coupled change is one edit (ADR 0040).
- `BoardDefinition` (ADR 0017): `BoardDefinition.all` lists the boards Sextant knows and `named(_:)` finds a layout's board by its `geometry`. Today that is `.voyager`: per key the Oryx index, matrix row/column, LED index, hand, cluster, row/column, Oryx stagger and home-row flag, as a Swift table generated once from `docs/research/data/voyager-matrix-led-map.json` and `voyager-geometry.json`. Also USB ids (`3297:1977|1978`, bootloaders `0791`/`1791`) and the flash window. Nothing else hard-codes 52, the PIDs or addresses (00 §8).
- `BoardGeometry` / `BoardLayout`: key-unit geometry, point layout, rotation-aware hit test, `neighbor(of:toward:)`. `BoardDefinition.geometry(navigator:)` builds a board's shapes; the UI sizes the board from them, never from Voyager constants.

### 2.3 Derived views of a layout

- `Legends` → `KeyLegend`, `ActionLegend`, `ResolvedLegend` (ported). Pure text and SF Symbol names.
- `LayoutIssues.check(_:)` → `[LayoutIssue]` (unknown keycode, missing layer, unreachable layer, macro too long, a macro step `SEND_STRING` can't type, empty combo, a tap dance slot that can't run, an ignored per-key tapping term, near size limit). A key's issue carries a `KeyRef` (layer, index, slot) so the UI can badge the cap; a combo's carries the combo's id. Combos also raise a combo over 6 keys, a duplicate trigger (another combo listening for the same keycodes, from any layer; a mod-tap or layer-tap is one keycode wherever it sits, `Key.isModTapOrLayerTap`, the rule the generator writes `MT()`/`LT()` by), a transparent, disabled or tap-dance key (`Key.comboRefusal`, the rule the generator refuses by), two keys typing one keycode (`KeyboardLayout.comboRepeatedKey`, which the generator refuses too), and rolling neighbors (a warning; `BoardGeometry.rollingPair`; ADR 0046). Each feature adds its check function and one call in `check` (ADR 0037).
- `OryxReference(string)`: parses `configure.zsa.io` URLs, `layout/revision` serials and bare ids.
- `changes(from:)` → `LayoutChanges`: `diff(from:)` plus changed setting ids (Navigator options included), combos added and removed compared by content (Oryx combo ids are positions), a Navigator flag (kind, side, automouse layer), and flags for the title and the layer order. Every own key of a layer the old layout lacks counts as added. History and Save Revision's message read it (ADR 0043).
- `ImportSummary(layout)`: layers, assigned keys, dual-function keys, labels, colour keys, macros.
- `FlashPath`: the `QK_BOOT` key and the chain of holds from layer 0 that reaches it (Build & Flash card B).
- `LayerHold.classify(layout:layer:pressed:)` → `base`, `momentary(heldBy:)`, `locked` or `pointer`: why the keyboard is on its highest layer, inferred from the keys held down, each resolved on the layer it went down on (MO, LT's hold, LM, a held TT or OSL hold; anything else locks; the Navigator's auto-mouse layer is the pointer's). The overlay HUD reads it (ADR 0050).
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

All ports are `Sendable` protocols with `async` methods and **typed throws**. Implementations are actors or `Sendable` structs. The one exception is `HotKeys`, a synchronous `@MainActor` protocol, because the system delivers hot-key events on the main thread (ADR 0048).

| Port | Methods (shape) | Adapter | Fake (tests) |
|---|---|---|---|
| `LayoutLibrary` | `entries()`, `load(id)` (with the working copy's content hash), `create`, `save`, `appendRevision`, `layout(ofRevision:in:)`, `rename`, `duplicate`, `trash`, `storeFirmware` / `firmware(revisionID:of:)`, `location(of:)`, `appLayerRules(of:)` / `saveAppLayerRules(_:for:)` (the sidecar, ADR 0054) | `PackageLibrary` (SextantStorage) | `InMemoryLibrary` |
| `OryxReader` | `layout(ref) -> KeyboardLayout`, `firmware(revisionID, expectedMD5) -> Data` | `OryxClient` (SextantOryx) | `FakeOryx` |
| `FirmwareGenerator` | `generate(layout, identity) throws -> GeneratedSource` (files + source map) | `QMKGenerator` (SextantBuild) | `FakeGenerator` |
| `Toolchain` | `status()`, `build(source, board) -> AsyncStream<BuildEvent>` (output, progress, then `.finished(BuildArtifact)` or `.failed(ToolchainError)`), `setUp() -> AsyncStream<SetupEvent>` (the consented one-time download) | `NativeToolchain` (SextantBuild) | `FakeToolchain` |
| `DeviceWatcher` | `events(for: board) -> AsyncStream<DeviceEvent>` (`.attached(ConnectedDevice)`, `.detached(id)`) | `IOKitDeviceWatcher` | `FakeDeviceWatcher` |
| `KeyboardLink` | `session(with: device, board:, commands: AsyncStream<KeyboardCommand>) -> AsyncStream<LiveEvent>` (serial, protocol version, layer, key down/up by matrix position, lighting and error replies, then `.ended`); writes `commands` only once paired and only within `KeyboardCommand.isAllowed(on:)` (ADR 0038) | `RawHIDLink` (its optional trace sink gets each report written and read, trimmed, as a `HIDTraceEntry`; ADR 0045), or `RefusingKeyboardLink` behind the gate (never reads its commands) | `FakeKeyboardLink` (records each session's commands) |
| `Flasher` | `flash(image, md5:, to: BootloaderDevice, board:, progress:)` | `DFUFlasher` (SextantDevice), always wired (ADR 0056) | `FakeFlasher` |
| `HeatmapStore` | `hours(of: layoutID, from:)`, `add(_ hour, to:)` (one hour, whole or not at all), `prune(before:)`, `clear(_ layoutID?)`: hourly counts by layer id and key index, per layout (ADR 0053) | `HeatmapFiles` (SextantStorage) | `FakeHeatmapStore` |
| `FrontmostAppWatcher` | `activations() -> AsyncStream<MacApp>` (the frontmost app now, then each that comes forward), `runningApps()`, `app(at: URL)`; a `MacApp` is a bundle id and a name, nothing else (ADR 0054) | `WorkspaceAppWatcher` (SextantApp, NSWorkspace notifications, no TCC) | `FakeFrontmostAppWatcher` |
| `HotKeys` | `register(layers:onPress:)`, `unregister()`, `setPaused(_:)`, `shortcut(forLayer:) -> HotKeyShortcut?`, `conflicts()`; `@MainActor`, since hot-key events arrive on the main thread (ADR 0048) | `KeyboardShortcutsHotKeys` (SextantApp, over sindresorhus/KeyboardShortcuts) | `FakeHotKeys` |

Small things that are not worth a port are injected as values: an `any Clock<Duration>` for debounce and timeouts, a `@Sendable () -> Bool` secure-input probe, a `@MainActor () -> Bool` for Settings › Keyboard's Follow by default, an `UndoManager`.

### 3.2 Use cases

| Use case | Isolation | Does |
|---|---|---|
| `Library` | `@MainActor @Observable` | Lists library entries; opens, creates (blank QWERTY), duplicates, renames, trashes layouts. One document per layout (`isOpen`, `close`), so one window per layout; writes pending autosaves on close and quit |
| `EditSession` | `@MainActor @Observable` | One open document: `layout`, `selection` (layer, key, slot, combo; `keyIndices` for several keys, with `keyIndex` as the anchor; `selectedKeys`, what edits act on, is the anchor alone while the window's `showsSeveralKeys` says it shows one key), every undoable edit from PrototypeKit's `EditorStore` (set action / code / modifiers / label / colour, paint, transparent, disable, swap, override, layer add / duplicate / rename / colour / move / delete, settings, title). Registers undo on the window's `UndoManager` with named actions and snapshots layout + selection. Feature edits live in `EditSession+<Feature>.swift`, built on the internal `edit(_:select:_:)`, `target(_:_:)` and `checkpoint(_:)`, with `library`, `revisionBaseline` and the setter of `revisions` internal too (ADR 0037). Debounced autosave (1 s) through `LayoutLibrary`, plus an immediate recovery copy of every change until its autosave lands (ADR 0032). Live issues recomputed per edit. Without an index, key edits act on every selected key (`targets()`) as one named undo step; the selection-wide extras (the picker's per-key assignment, macros on several keys, Copy To Layer, cut/copy/paste through the domain's `CopiedKeys`, Copy Layer To) live in `EditSession+MultiSelect` (ADR 0047). History's operations (`EditSession+History`): `revisionLayout(_:)`, `recordRevision(_:)` (appends any layout and makes it the "Edited" baseline) and `restoreRevision(_:)` (checkpoint, append "Restored revision N", then one undoable edit keeping the title; ADR 0043). `EditSession+Settings`: `resetSettings()`, every changed setting the layout shows (`KeyboardLayout.changedSettings`) back to its default in one step (ADR 0040). |
| `ImportFromOryx` | `@MainActor @Observable` | Steps: read link → fetch layout → fetch Oryx's firmware with md5 (optional) → convert; an `ImportSummary` preview; saves as a new layout or as a revision of an existing one with the same Oryx id, checkpointing local edits first (ADR 0024). Strips " [fork]". |
| `LiveSession` | `@MainActor @Observable` | Consumes `DeviceWatcher` and `KeyboardLink`. State: connection (none / connected / bootloader / held by another app / access off), serial and `FirmwareMatch` (ADR 0019), active layer, pressed key indices (matrix → index via `BoardDefinition`), Follow mode, secure-input pause. Coalesces to ≤ 60 Hz, reconnects with backoff, never stores or logs events (ADR 0023). `activity()` streams every key-down (with its layer), key-up, layer change and lighting reply before the coalescing; presses and layers are silent during secure input (checked at every event), replies are not; it keeps keys paired, sending the key-ups of the keys down when secure input hides an event or the session ends, and lets the first layer report after secure input through (ADR 0050). `send(_:)` queues a `KeyboardCommand` for the paired session and `canSend` says whether one is open; it throws when there is no keyboard, access is off, Keymapp holds it, the session isn't paired or the value is out of range (ADR 0038). It tracks whether Live View took the keyboard's lights and which `05 00` are unanswered: `releaseLights()` sends one only when due (with no session paired, or Live View turned off between two sessions, the next session to pair sends it), `releaseLightsAndWait()` (quit) waits for the `08 00` replies, and `stopLive()` with the lights taken reads as off at once but ends the session only after the reply, bounded by an estimate of the queued writes (12 ms each, `waitForQueuedWrites()`) plus 500 ms; turning it on again meanwhile reads as connecting and pairs once that ends (ADR 0051). Follow turns on at connect only when `followsOnConnect` says so. `isWritingFirmware` is up from a Build & Flash's validate until its verify records the flash or fails; quitting waits on it, before and after the last autosave. `flashProgress` is that write in 0–1 (erasing the first half, writing the second) in 5% steps, for the menu bar's arc (ADR 0049). |
| `RawHIDTrace` | `@MainActor @Observable` | The Developer raw-HID log: a 500-entry ring buffer fed by the link's trace sink, in wire order. Off at launch, drops everything while off and while secure input is on (asked per report), cleared when turned off, never written to disk or os_log. App-wide, on `SextantServices` (ADR 0045). |
| `OnKeyboard` | `@MainActor @Observable` | App-wide: which library entry, revision and layout the keyboard runs, from `LiveSession`'s serial alone (works with live access off). An Oryx serial names its import revision; a Sextant serial names the working copy when the fingerprint matches, else the newest matching flash revision; never unflashed edits (ADR 0039). Re-resolves on serial change, library refresh and the end of a flash. `moveKeyboard(toLayer:dryRun:)` sends `.moveToLayer(n)` only over a paired Live View session and only to a layer of `running`'s layout (layer 0 alone when it's unknown), else throws a `LayerMoveRefusal` the menus show (ADR 0048). |
| `LayerShortcuts` | `@MainActor @Observable` | App-wide: the global layer shortcuts over the `HotKeys` port. Off by default; on registers ten (layers 0–9), off unregisters them, saved through a closure. A press moves the keyboard through `OnKeyboard`, or sends nothing; `refusal` then says why as things stand now, and clears once that press would send. `suspend()`/`resume()` let Record Key and Record Steps take ⌃⌥ digits. Lists `conflicts`, gives menus a layer's shortcut only while it can fire, and judges a recorded shortcut (`problem(with:forLayer:)`: needs ⌃ or ⌘, no two layers alike; ADR 0048). |
| `AppLayerSwitcher` | `@MainActor @Observable` | App-wide App Layers (ADR 0054). Follows `FrontmostAppWatcher`; the app in front at launch only sets where switching starts. An activation that stays in front for 150 ms (on the injected clock; a burst moves the keyboard once, for the last) is decided by `AppLayerRules.target(activated:previous:in:)` against the rules of the layout the keyboard runs (`OnKeyboard.running`), checked against its flashed layout, and sent through `OnKeyboard.moveKeyboard(toLayer:)` once no key is held, even when the keyboard reports that layer already. Sextant's own activations (`ownBundleID`) are ignored. Sends nothing unless that layout's switch is on with a rule enabled, Live View is paired, Keymapp doesn't hold the board and the keyboard isn't in flash mode; nothing is queued or replayed. `state(for:)` says why a layout's rules are off or paused (the `LayerMoveRefusal` of a dry-run move, or another layout flashed), `applied(for:)` what holds now. Keeps the rules per layout (`load`, `setRules`, saved in order through the port; an unreadable sidecar is never overwritten; a failed save stays in `saveError(for:)` until `retrySave(for:)` or a later save lands) and the last 20 switches in memory, app names only. |
| `LightingPreview` | `@MainActor @Observable` | App-wide: the keyboard lighting preview (RGB takeover). One window holds it (`claim(for:title:)`, refused with a `LightingPreviewRefusal` while another does or Live View is off); its frames (one color per LED, from `KeyboardLayout.ledColor(layer:index:)`) go through `LiveSession.send` only over a paired session: the first of a session as `05 01`, `09` with the most common color and `06` for the rest, later ones as the changed lights (or a fill when that's fewer writes), each batch waiting out `LiveSession.waitForQueuedWrites()` so at most one is queued and the latest frame wins. Brightness scales colors on the Mac. Every release goes out last through `LiveSession.releaseLights()`; a session that ends forgets what it was sent and the next paired session gets the whole frame; Live View off ends it. Any `08 00` makes it resend the next frame in full (ADR 0051). |
| `HeatmapRecorder` | `@MainActor @Observable` | App-wide: Heatmap recording, off until the user turns it on (Settings › Privacy, saved through a closure). Counts `activity()`'s key-downs by the layer id they went down on, and the keyboard's moves between layers, into hourly buckets, only over a paired Live View session and only for the library layout `OnKeyboard` resolves; the feed's secure-input silence keeps password typing out. Writes every minute on the injected clock, when turned off and at quit; prunes by retention; clears a layout's counts, or all; drops the counts of a layout Sextant moved to the Trash (`Library.trashed`). Windows read a snapshot (never during a write) plus what was counted since, including a write still landing (`unwritten(of:from:after:)`, observed through `changes`), over a range that slides with `hour`. `lastError` holds a failed read, write, prune or clear until that kind succeeds. Words per minute come from the last minute's presses, in memory only (ADR 0053) |
| `BuildFlashSession` | `@MainActor @Observable` | `source(of:)` gives the QMK source a build would compile (of the working copy, or of a revision's layout), and `currentArtifact` gives the last build while the layout is unchanged, for File ▸ Export (ADR 0044). The §7 state machine: issues gate → generate → compile (progress, log mapped through the source map) → size → wait for bootloader → validate image → flash → wait for re-enumeration and serial check → record a revision of the build (`recordRevision`, so it holds exactly what was flashed and the open window lists it; ADR 0043) and keep its image with `storeFirmware` → then release flash mode (`OnKeyboard` relies on that order, ADR 0039). Cancel is refused during erase / write / verify. `buildAndFlash(connectedKeyboard:revision:)` takes a `RevisionLayout` to build and flash a revision instead of the working copy (History's Flash This Revision…); `firmwareSize(of:)` reads a revision's kept image and the change since the newest earlier revision with one (ADR 0043). |

### 3.3 Hardware gate

The real flasher and raw-HID link are always wired, and each writes to the keyboard only after the user starts it: Build & Flash (ADR 0056), and Live View, which `LiveSession.startLive()` turns on from the toolbar, the Keyboard menu or the Device popover; until then a plugged-in keyboard is `.liveOff` and nothing is written (ADR 0057). Read-only enumeration (`IOKitDeviceWatcher`) is always on.

## 4. Adapters

- **`SextantStorage.PackageLibrary`** (actor): §6 format; atomic writes (`Data.write(options: .atomic)`); SHA-256 content hash of the canonical JSON; per-revision Oryx firmware; trash via `FileManager.trashItem`.
- **`SextantStorage.HeatmapFiles`** (actor): `~/Library/Application Support/Sextant/Heatmap/<layout id>/<yyyy-MM-dd>.json`, one file per UTC day of hourly counts, outside the packages (ADR 0053); whole-file atomic writes; a damaged or newer file reads as empty and is replaced by the next write for its day; a count below 1 is left out and one past `HeatmapHour.countLimit` held to it, sums saturate rather than trap, and a layout folder pruned empty is removed.
- **`SextantOryx.OryxClient`** (struct over an injected `URLSession`): `POST https://oryx.zsa.io/graphql` with the `getLayout` query and a descriptive User-Agent; `GET /firmware/{rev}` with md5 enforced. Never logs in, never mutates. Contract tests use a `URLProtocol` stub with fixture JSON from `docs/research/oryx-examples/` (the public samples come from the reference folder).
- **`SextantBuild.QMKGenerator`** (struct, pure): emits `keymap.c`, `config.h`, `rules.mk`, `keymap.json` (and `i18n.h` when needed) following research 02 §4, keeping `zsa/oryx`, `zsa/defaults` and the Navigator modules. Emits a source map (keymap.c line → `KeyRef`). Settings follow Oryx's output where its samples show it and Sextant's own mapping where they don't (ADR 0040); a setting with neither stops the build by name (ADR 0020).
- **`SextantBuild` toolchain** (ADR 0033): `NativeToolchain` runs `qmk compile` on the Mac with Arm's GCC 12.2.1 (ZSA's release), GNU make 4 and Python with the `qmk` CLI, against ZSA's fork at pinned commits, all in `~/Library/Caches/com.sextant.app/Toolchain` (QMK can't take spaces in paths). Every build runs under `sandbox-exec`: no network, no reads in the home folder outside the toolchain, writes only to the build folder and its image. `ToolchainInstaller` (one actor, shared by every window) fills the folder only from the setup step, with consent: each artifact pinned by URL, size and SHA-256 (`ToolchainPins`; files of 16 MB or more come as eight parallel byte ranges joined in order, since Arm's server limits each connection to about 140 KB/s, with a whole-file fallback), pruned while unpacking, wheels installed by pip from the verified files only, and a marker written last. Sextant appends the DFU suffix itself (`FirmwareImage.withSuffix`). Output streams through the shared `file:line:col: error:` diagnostic and size parsers.
- **`SextantDevice.IOKitDeviceWatcher`** (actor): `IOServiceAddMatchingNotification` for VID `0x3297`, PIDs from `BoardDefinition`; reads serial and `bcdDevice`. Read-only.
- **`SextantDevice.RawHIDLink`** (actor on its own serial dispatch queue): IOHIDManager matching usage page `0xFF60` / usage `0x61` only, opened non-exclusively, 32-byte reports. Commands join the session's input loop, which drops them until paired, and layers and presses from a board another host paired wait for that pairing too, so `canSend` never turns true early (ADR 0051); a writer task then writes them with the handshake's 5 ms pacing, so reports never wait behind writes. Only `04 01`, `05`, `06` and `09` can be encoded, and a layer move is followed by `01` to resync the layer (research 03 O2). Oryx protocol v5 parsing and encoding live behind an internal `HIDTransport` protocol, so both are tested with a fake transport.
- **`SextantDevice.DFUFlasher`** (actor on its own serial queue): DFU 1.1 + DfuSe over an internal `USBControlTransport` protocol, implemented with `IOUSBHostInterface.sendDeviceRequest`. Guards, all unit-tested against a fake DfuSe device: address window `[0x08002000, 0x08042000)` on every erase and write, never MASS_ERASE, image re-validated for the connected PID, md5 check, GETSTATUS polls capped (count and total time), `dfuERROR` is failure, CLRSTATUS once at start only.
- **`SextantUI`**: views and `@Observable` view models. View models call use cases only; they never see adapters. One `LayoutWindowModel` per window owns the open `EditSession`, that layout's `BuildFlashSession` and its `HistoryModel` (the History page's selection, comparison and cached revision layouts; ADR 0043); `LiveSession`, `OnKeyboard` and `LightingPreview` are shared. The window feeds the lighting preview the shown layer's colors while it holds it on the Lighting lens's board, and releases it when it leaves that board, opens another layout or closes (`Lighting/KeyboardLighting.swift`, ADR 0051). Folders follow the window's regions (`Sidebar`, `Canvas`, `Board`, `Inspector`, `Picker`, `Lighting`, `Import`, `FirmwareSettings`, `History`, `Combos`, `Settings`, `Device`, `BuildFlash`, `Commands`, `Window`, `Theme`), plus `MenuBar`: the menu bar extra's label (`MenuBarLabelState` draws one image, the glyph and layer number, since its label renders only an Image and a Text), its panel drawn from a `MenuBarPanelState` value, `WindowRouter` (opens the keyboard's layout window for the panel and Window ▸ Main Window, and holds a Build & Flash for that window to take) and `AppPresence` (the Dock icon: `.accessory` only with no layout window and both menu bar settings on; ADR 0049), and `Export`: File ▸ Export's one save panel (`pendingExport`, `ExportFile`) and `BoardImage`, the static board that the PNG, the PDF and Print Layout… draw (ADR 0044). Window-wide state reaches deep views through the environment (`brush`, `swapsKeys`, `layoutWindow`, `boardDisplay`) rather than new view parameters; sheets and alerts hang off one `windowPresentations` modifier. A board gesture must be gated on the lens (ADR 0029). The window's `destination` (a layer or a document page) routes the centre and inspector. Combos and Changes are board modes of their destinations, not lenses. Features plug in through values rather than edits: a `BoardPick` takes the board's clicks (prompt in the lens lane, esc cancels), and an `AssignTarget` takes the picker's keycode (ADR 0037). A board mode (Changes, Combos, Heatmap) marks caps by setting `KeyCapModel.decoration` (`CapDecoration`: opacity, ring, a top-right badge, a top-left number, a heat fill and count), not by editing `KeyCap`; a number of two digits or more is drawn as text in a `NumberDisc`, since SF Symbols squeezes two digits past reading on a cap (slice 2.1 added that one branch to `KeyCap`); `KeyText.value` speaks the badge, number and count (ADR 0037). Changes also hands the board a `BoardDisplay` (a revision's layout and layer): the board draws it read-only in the document's geometry, so no key moves (ADR 0043). Combos (`Combos/`: `CombosModel` behind `LayoutWindowModel.combos`, the canvas, cards, inspector and `ComboOverlay`) chooses keys through a `BoardPick` over a window-held draft, picks the output through an `AssignTarget`, and draws traces and output pills in one overlay line in BoardView, placed by `ComboPills` so none covers a legend (ADR 0046). The board's cut, copy and paste are SwiftUI's pasteboard commands on the focused board; `KeyPasteboard` writes a `com.sextant.keys` item provider and reads a given pasteboard, so tests use a private one, and `CopiedKeys` validates what is read (ADR 0047). `Overlay/` is the app-wide overlay HUD, owned by no window: `OverlayHUD` feeds `OverlayModel` (when to show what, on an injected clock) from `LiveSession.activity()`, `OnKeyboard` and Settings › Keyboard (`feed`, testable on a real `LiveSession`), and shows it in `OverlayPanel`, a nonactivating `NSPanel` that never becomes key or main, ignores the mouse and drops its content once ordered out (a hidden hosting view would still redraw at every key event), with `HUDView` (or the `HUDPill` reminder) on an `NSGlassEffectView`. A layout window reports the layer its board shows while it is key (`reportsShownLayer`), so the HUD doesn't repeat it (ADR 0050). `AppLayers/` is the App Layers page: `AppLayersModel` behind `LayoutWindowModel.appLayers` (the selected rule and Add App…'s apps) edits the app-wide `AppLayerSwitcher`'s rules for the window's layout, which save at once outside the document's undo; the page, `AppLayersInspector`, the lane's app-rule capsule and the menu bar's App Layers row read the switcher's `state(for:)`, `applied(for:)` and `history(for:)`, the switches that layout's own rules made (ADR 0054). Select Key by Pressing It (`Board/SelectByPress.swift`, behind `LayoutWindowModel.selectByPress`) reads `LiveSession.activity()` for the next key-down and its key-up and watches with `Observations` for what ends it, timing its waits on the window's injected clock; Record Key's local monitor also swallows the Mac's copy of that press (ADR 0052). `Heatmap/` is the Heatmap lens: `HeatmapModel` behind `LayoutWindowModel.heatmap` (the range, and the open layout's counts as last read from the app-wide `HeatmapRecorder` plus what it has counted since, cached by its `changes` for the board's caps), the caps' heat and counts through the decoration hook, the lens lane's capsule (which also reads the counts and asks before Turn On and Clear), the strip and the inspector; its exports go through File ▸ Export's save panel, and `TypingStats` is the menu bar's typing line (ADR 0053).

### 4.1 Composition root (`SextantApp`)

`@main struct SextantMain` builds the concrete adapters (the raw-HID link and the flasher are always wired, and write only after the user starts Live View or Build & Flash, ADRs 0056 and 0057; the link gets the `RawHIDTrace` sink, ADR 0045), starts `LiveSession`, `OnKeyboard`, `LayerShortcuts`, `LightingPreview`, the overlay HUD, `HeatmapRecorder` (over `HeatmapFiles`, with Settings › Privacy's saved choices) and `AppLayerSwitcher` (over `WorkspaceAppWatcher`), and hands `SextantUI` a `SextantServices` value: `Library`, `LiveSession`, `RawHIDTrace`, `OnKeyboard`, `LayerShortcuts`, `LightingPreview`, `OverlayHUD`, `HeatmapRecorder`, `AppLayerSwitcher`, and factories for `ImportFromOryx` and `BuildFlashSession`. The UI never sees an adapter. `SextantScenes` also gets the layer shortcuts' recorder as a view factory (`LayerShortcutRecorder`), so the UI never imports KeyboardShortcuts (ADR 0048), and a `WindowRouter` with its `AppPresence`, built once there because they outlive every window and scene value (ADR 0049). The app delegate ends the lighting preview when the Mac goes to sleep, and on quit (after `Quitting` decides to quit) with `LiveSession.releaseLightsAndWait()` (ADR 0051), then writes the Heatmap's last counts, so a slow disk never keeps the lights (ADR 0053). Command-line flag: `--import <oryx.json>` imports a layout file into the library at launch. Snapshots are a separate tool: `swift run SextantSnapshots <dir> [--only a,b]`. No singletons: everything flows from `SextantMain`.

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
  layout.json               the working copy: KeyboardLayout in Oryx revision shape, pretty-printed, sorted keys, plus
                             Sextant's own top-level "macroDrafts":[{"id":…,"macro":{…}}] when it has unassigned macros
  revisions/
    0001-3b9f2c1e.json      {"id":…,"number":1,"parent":null,"createdAt":…,"source":"import|flash|save",
                             "message":…,"contentHash":"sha256:…","layout":{…}}   append-only, never rewritten
  firmware/
    <revisionId>.bin        an Oryx-built image (under Oryx's revision id) or a flashed Sextant build (under the flash
                             revision's id, for History's size delta)
    <revisionId>.bin.md5
  app-layers.json           App Layers: {"formatVersion":1,"isOn":false,"rules":[{"bundleID":…,"name":…,"layerID":…,
                             "leaving":"returnToMain|stay","isEnabled":true}]}; missing means no rules (ADR 0054)
.recovery/<UUID>.json       the latest edits until their autosave lands (ADR 0032)
```

- Folder names are for humans; identity is `meta.json` `id`. Renaming a layout rewrites `meta.json` and renames the folder.
- `contentHash` is SHA-256 over the canonical (sorted-keys) JSON of `layout`, written as `sha256:<hex>`. It powers "Edited since revision", "Flash Oryx's build" (hash equals an imported revision) and future sync.
- `formatVersion` greater than the build's is refused with a typed error, never misread. This build reads 2. It writes 1 until a package holds macro drafts, then 2 (meta.json first, so drafts never sit under format 1), and keeps it at 2 after they go, since revisions may hold them. An older build therefore refuses drafts rather than dropping them at its next save (ADR 0042).
- The Heatmap's counts are never in a package: they live beside the library (§4, ADR 0053), so exports, Duplicate, revisions and the content hash never carry typing data.
- Macros on keys and combos stay inline, in Oryx's shape. `macroDrafts` is written only when non-empty, so a layout without drafts hashes exactly as before.
- `app-layers.json` is a sidecar outside `layout.json`: saving it leaves the content hash, `modifiedAt`, the revisions, "Edited" and the `sx-` fingerprint as they were. It has its own `formatVersion` (a newer one is refused, and Sextant then never overwrites it). Duplicate copies it; Trash takes it with the package (ADR 0054).

## 7. Errors

- Each port has a typed error enum in the application layer (`LibraryError`, `OryxError`, `BuildError`, `ToolchainError`, `DeviceError`, `FlashError`); domain has `FirmwareImageError`, `OryxDecodingError`, `LayoutError`. Ports and use cases use typed throws (`throws(OryxError)`); adapters map platform errors at the boundary.
- Anything the user sees conforms to `LocalizedError` with the spec's copy (§8.1 table, §12.6 catalog): sentence case, what happened, what it means, what to do.
- No `try!`, `fatalError` or force-unwrap outside tests, except for compile-time-constant data proven by a test (the embedded catalogs).
- Logging: `os.Logger(subsystem: "com.sextant.app", category: <layer>)` with categories `domain`, `application`, `storage`, `oryx`, `build`, `device`, `ui`, `app`. Key events and typed text are never logged; the developer raw-HID log stays in memory (ADR 0045); the Heatmap writes only hourly counts of presses per key position and of layer changes, and only once the user turns it on (ADR 0053).

## 8. Testing

| Layer | Kind | Where |
|---|---|---|
| Domain | unit (Swift Testing) | model, codec round-trip on all 7 Oryx JSON files, legends, catalog search, geometry, issues, diff, image validation, contrast thresholds for the 2 user colours and 10 swatches |
| Application | unit with in-memory fakes of every port | undo/redo with named actions, autosave debounce, import flow, live session state, build/flash state machine including refusal paths |
| Storage | contract (temp directory) | create / load / save / revisions / rename / trash / formatVersion refusal; Heatmap day files (merge, prune, clear, damaged files) |
| Oryx | contract (`URLProtocol` stub) | request shape (query, no auth header, User-Agent), envelope decode, not-found / offline / other-board errors, md5 mismatch |
| Build | golden | generate from the author's own Oryx layout in `docs/research/oryx-examples/` and, when `SEXTANT_REFERENCE` is set, the four public samples kept in the reference folder, and diff against their unzipped Oryx source zips, normalising whitespace and DUAL_FUNC placeholder numbering; diagnostics and size parsers |
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
