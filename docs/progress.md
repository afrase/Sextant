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

## In flight (resume here after a context reset)
- **Integration review** workflow (task `w4ecr4661`, run `wf_c6181f9f-913`, base `3e4404a`): four cross-slice lenses (contracts, hardware safety, lifecycle, untrusted input), each verified adversarially; one fixer on branch `fix/integration` in a worktree under `.claude/worktrees/`; then a re-verify. Output: `/private/tmp/claude-501/-Users-aaron-Developer-Sextant/2f67ef65-26bf-4a5a-8d56-49a6645776d3/tasks/w4ecr4661.output`; per-agent results in the run's `journal.jsonl`. When done: read confirmed/refuted/fix/reverify, review `git diff main..fix/integration`, merge if the gate passes, record ADRs for any significant decisions, update this file.

## How we work (agreed with the user)
- Every phase gets an adversarial review: independent lenses try to refute, confirmed findings get fixed, fixes get re-verified before landing.
- Prefer community libraries and tools (ADR 0018); ask before adding new packages or downloads.
- Every significant decision gets an ADR in `docs/adr/`, indexed in `docs/decisions.md`.
- Subagents run with ponytail mode (the SessionStart hook fires for them) and self-review with `ponytail:ponytail-review`.
- Commit only when `scripts/check` passes; never push.

## Next
1. Merge the integration fixes.
2. Before the next fan-out, split the window's shared views into separately owned files (sidebar sections, detail routing, inspector routing, sheet presentation) so parallel UI slices don't collide.
3. Phase B fan-out (same adversarial pipeline), five UI slices: (a) key inspector, step 4; (b) palette, keycode picker and Record Key, step 5; (c) layers management and the Lighting lens, steps 6–7; (d) import sheet, Firmware Settings page, Settings scene, empty states and onboarding, steps 8, 11, 12; (e) device card, Device popover, Follow and presses, and the Build & Flash sheet over `LiveSession` / `BuildFlashSession` (replacing the `onBuild` hook), steps 9–10. Remaining MVP steps in detail: 4 key inspector, 5 picker/palette/Record Key, 6 layers, 7 lighting, 8 import sheet, 9 device card/popover/Follow/presses, 10 Build & Flash sheet (feeding `ActivityState`, replacing `onBuild` with `BuildFlashSession`), 11 Firmware Settings, 12 Settings scene, empty states, onboarding.
4. Toolchain setup step (download and verify the VM images) once the user approves the download.
5. Final report per `docs/prompts/lead-architect.md` (what works, milestones, decisions, deviations, what waits on the user, the ponytail-debt ledger via `ponytail:ponytail-debt`).

## Known gaps and notes
- Security: the generator validates every data-derived token (ADR 0020), after a background security review found C injection; covered by hostile-input tests.
- Build slice leftovers: the Navigator `sensitivity` (trackball CPI) has no range check (still integer-only, so no injection); a cancelled build can leave a uniquely named temp folder behind (`shortcut:`); the VM path is compiled but has never booted.
- Device slice: an interface seized by another app after pairing goes unnoticed (reports just stop; `shortcut:`); `IOHIDDeviceSetReport` has no timeout.
- `BuildFlashSession.stop()` must be called when a document closes (a waiting run would otherwise flash the next keyboard put in flash mode); the UI's `.stop` on window close does this once Build & Flash is wired.
- The "hold" marker crowds the signal bar on hold-only keys (board step).
- `Library.rename`, `duplicate` and `trash` bypass an open `EditSession`; route renames of open layouts through `EditSession.setTitle` when the sidebar menu is built (step 6).
- Domain keycode names and legends are English data, not localized (ADR 0016).
- The `.app` was built and signature-checked, not launched by the agent; the UI was checked with offscreen snapshots.

## Blocked / waiting on the user
- **Hardware (ADR 0012):** raw-HID writes (pairing for the live layer) and flashing. Built against fakes; wired off by default.
- **Container image (ADR 0018):** the build backend is container-first; the ~1 GB image downloads only from the first build's setup step, with the user's consent. Not downloaded yet.

## Deviations from the spec
- All-null keys render transparent, not Disabled (ADR 0015): Oryx's generated firmware makes them `KC_TRANSPARENT`.
- `layer.display` for #00F0FF is #00A3AD, not "about #00959E": the spec's own 3:1 rule stops there.
- Cap size uses the board's own size in pitch units (ADR 0017); for the Voyager this is the spec's formula.
