# Progress

Read this first after a context reset. Plan: `docs/prompts/lead-architect.md`. Design: `docs/architecture.md`. Decisions: `docs/decisions.md` and `docs/adr/`.

## Done
- **Code design:** `docs/architecture.md`, ADRs 0006–0025.
- **Scaffold:** one package, a target per layer (`SextantDomain`, `SextantApplication`, `SextantStorage`, `SextantUI`), the composition root `SextantApp`, the dev tool `SextantSnapshots`. Scripts: `scripts/check` (lint, warnings-as-errors build, tests), `scripts/bundle` (signed `.app`), `scripts/strings` (String Catalog sync), `scripts/notarize` (user only).
- **Milestone 1:** the user's layout renders read-only: `PackageLibrary` (storage) → `Library` / `EditSession` (use cases) → `LayoutWindowModel` → `BoardView`. Reviewed with a four-lens workflow; 34 confirmed findings fixed.

## How to run
- Gate: `scripts/check`.
- Snapshots: `swift run SextantSnapshots <dir> [--only window-light,board-brdsys-dark]`.
- App: `scripts/bundle`, then `open .build/Sextant.app --args --import docs/research/oryx-examples/my-layout-KlgM7-40xJ7M.json` (the import writes to `~/Library/Application Support/Sextant/Library/`).

- **Ports and shared domain types** for Oryx, generator, toolchain, device watcher, keyboard link and flasher; adapter skeletons.
- **Tooling (ADR 0018):** pinned community packages; `scripts/check` runs swift-format, SwiftLint (quality + layer import rules), a warnings-as-errors build, tests and a Periphery report.
- **Security fix:** imported numbers could crash Sextant (`Int(Double)` traps); fixed and tested.

- **MVP slices merged** (workflow `mvp-slices`, 35 agents, each slice implemented, reviewed by three adversarial lenses, verified, fixed and re-verified; 45 findings fixed): QMK generator with golden tests on all five Oryx samples, container and native toolchains, live issues, flash path (`slice/build`); device watcher, raw-HID link and DFU flasher with every guard tested on fakes (`slice/device`); Oryx client, import use case, stored Oryx firmware (`slice/oryx`); window skeleton, commands, full board (`slice/ui`, spec steps 2–3); `LiveSession`, `BuildFlashSession`, firmware identity, hardware gate (`slice/usecases`). Integration fixes: Add-as-Revision save errors surface; "Edited" uses the stored content hash. ADRs 0019–0025.
- **Composition root wired:** `SextantServices` (library, live session, import and Build & Flash factories); raw HID and flashing behind `SextantHardwareEnabled` (ADR 0012).
- **Integration review** (workflow `integration-review`, 10 agents: four cross-slice lenses, verify, fix, re-verify; 10 of 24 findings confirmed and fixed): one window per layout (a sidebar click on a layout open elsewhere brings that window forward); quitting waits for pending autosaves; an import moves the "Edited" baseline; build size is measured against the 120 KiB linker window; every GD32 (`0x1791`) image is refused; macro pauses are bounded to 0...5000 ms; issue de-duplication is linear; `load` hashes `layout.json` itself; folder names fit APFS's 255 UTF-16 units; the secure-input poll runs only while a keyboard is connected.

## How we work (agreed with the user)
- Every phase gets an adversarial review: independent lenses try to refute, confirmed findings get fixed, fixes get re-verified before landing.
- Prefer community libraries and tools (ADR 0018); ask before adding new packages or downloads.
- Every significant decision gets an ADR in `docs/adr/`, indexed in `docs/decisions.md`.
- Subagents run with ponytail mode (the SessionStart hook fires for them) and self-review with `ponytail:ponytail-review`.
- Commit only when `scripts/check` passes; never push.

- **Window split for parallel work:** sidebar sections, detail and inspector routing, presentations, canvas bands and menu groups each have a file; the window gets `SextantServices`; `openKeycodePicker()` / `openImport(_:)` are the cross-slice hooks. Snapshot windows each get their own `Library` (one window per layout had left every window scene after the first empty).
- **Never lose work (ADR 0032, the user's request):** every change is copied at once to `<library>/.recovery/<id>.json` until its autosave lands; opening a layout restores a newer copy, and the lens lane says so until OK.
- **Phase B merged (MVP steps 4–12)** (workflow `phase-b-slices`, 35 agents; each slice implemented, reviewed by three lenses, verified, fixed and re-verified; 63 confirmed findings): the key editor with drag to swap (ADR 0027); the command palette, keycode picker and Record Key (ADR 0028); layer management and the Lighting lens (ADR 0029); the import sheet, Firmware Settings page, Settings scene, layout Rename/Duplicate/Trash, New Layout (blank QWERTY) and the Welcome (ADR 0030); the device card, Device popover, Follow, live presses and the Build & Flash sheet over `BuildFlashSession` (ADR 0031). Merge fixes: one `HexColor(Color)`; Key ▸ LED Colour swatches; the context strip scrolls to the current layer; the layer inspector uses the shared row style; the open layout can't be trashed while its flash writes; the generator builds Oryx's `ALL_T`/`MEH_T` holds in dual-function keys and tap dances; quitting ends text editing before the last save.

- **Phase B integration review** (cross-slice lenses, verify, fix; 27 confirmed findings, 21 distinct, all fixed): the generator presses Hyper, Meh and chorded modifier holds as real modifiers (`register_mods(MOD_BIT(…))`: `register_code16` made them weak, and QMK drops weak modifiers at the next key press); quitting waits for a firmware write (`LiveSession.isWritingFirmware`) and asks before quitting with an unsaved edit; a window can't close while its flash writes; flash mode is claimed per Build & Flash run, not per layout; a failed autosave shows in the lens lane with Try Again (`flush()` retries it), above the restored-edits notice, which now shows over live errors, is announced to VoiceOver, and reads "Restored edits that hadn't been saved"; renaming a closed layout keeps its recovery copy; Record Key assigns to the layer it started on (Follow can move the board meanwhile); ⌘⌫ / ⇧⌘⌫ are off while any text field may have focus; New Window lost ⌥⌘N, which is Legends ▸ Key Numbers (this amends ADR 0030's "New Window moves to ⌥⌘N"); the palette floats over the Firmware Settings page, and its setting rows open that page at their section; layer commands and opening a layout return to the board; New Layout and imports open in the asking empty window (also one showing a load error), and only a Welcome window picks up a layout that arrives (`--import`); a duplicate starts with a revision, so it opens unedited; the toolbar names the board with no layout open; Follow's tooltip says why it is off; Layouts rows show "On keyboard"; the device card's [Import] needs a real Oryx serial; a late layer-name commit can't reach a layout the window let go.

## In flight
- Nothing.

## Next
1. Done: the integration review checked the user's notes (2026-10-11): the Welcome with three cards, import offers for an unknown keyboard (Welcome card, device card [Import], Import from Connected Keyboard), and the restored-edits notice.
2. Toolchain setup step (download and verify the VM images) once the user approves the download.
3. Final report per `docs/prompts/lead-architect.md` (what works, milestones, decisions, deviations, what waits on the user, the ponytail-debt ledger via `ponytail:ponytail-debt`).

## Known gaps and notes
- Security: the generator validates every data-derived token (ADR 0020), after a background security review found C injection; covered by hostile-input tests.
- Build slice leftovers: the Navigator `sensitivity` (trackball CPI) has no range check (still integer-only, so no injection); a cancelled build can leave a uniquely named temp folder behind (`shortcut:`); the VM path is compiled but has never booted.
- Device slice: an interface seized by another app after pairing goes unnoticed (reports just stop; `shortcut:`); `IOHIDDeviceSetReport` has no timeout.
- The "hold" marker crowds the signal bar on hold-only keys (board step).
- Domain keycode names and legends are English data, not localized (ADR 0016).
- Integration review leftovers: the keycode picker still assigns to the layer the board shows when Follow moves it (its preview and scope token move with it, so the user sees where it lands); two Welcome windows can race for a layout one of them made (the other may open it first).
- The `.app` was built and signature-checked, not launched by the agent; the UI was checked with offscreen snapshots. Not checkable offscreen, so try them in the app: a Lighting-lens drag across keys paints and never swaps; the context strip scrolls to the current layer at 1120×640; a label typed and not committed survives ⌘Q; dark-mode contrast of controls inside the inspector (the offscreen renderer draws them wrongly).

## Blocked / waiting on the user
- **Hardware (ADR 0012):** raw-HID writes (pairing for the live layer) and flashing. Built against fakes; wired off by default.
- **Container image (ADR 0018):** the build backend is container-first; the ~1 GB image downloads only from the first build's setup step, with the user's consent. Not downloaded yet.

## Deviations from the spec
- All-null keys render transparent, not Disabled (ADR 0015): Oryx's generated firmware makes them `KC_TRANSPARENT`.
- `layer.display` for #00F0FF is #00A3AD, not "about #00959E": the spec's own 3:1 rule stops there.
- Cap size uses the board's own size in pitch units (ADR 0017); for the Voyager this is the spec's formula.
- Drag to swap is a gesture, not `.draggable`/`.dropDestination`, and the source cap doesn't lift (ADR 0027). A layer key's behaviour and target are pop-up menus, not a segmented control and chips; the inspector's LED row is a colour well plus No Colour, with the swatches in Key ▸ LED Colour (ADR 0027).
