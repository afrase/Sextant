# Progress

Read this first after a context reset. Plan: `docs/prompts/lead-architect.md`. Design: `docs/architecture.md`. Decisions: `docs/decisions.md` and `docs/adr/`.

## Done
- **Code design:** `docs/architecture.md`, ADRs 0006–0018.
- **Scaffold:** one package, a target per layer (`SextantDomain`, `SextantApplication`, `SextantStorage`, `SextantUI`), the composition root `SextantApp`, the dev tool `SextantSnapshots`. Scripts: `scripts/check` (lint, warnings-as-errors build, tests), `scripts/bundle` (signed `.app`), `scripts/strings` (String Catalog sync), `scripts/notarize` (user only).
- **Milestone 1:** the user's layout renders read-only: `PackageLibrary` (storage) → `Library` / `EditSession` (use cases) → `LayoutWindowModel` → `BoardView`. Reviewed with a four-lens workflow; 34 confirmed findings fixed.

## How to run
- Gate: `scripts/check`.
- Snapshots: `swift run SextantSnapshots <dir> [--only window-light,board-brdsys-dark]`.
- App: `scripts/bundle`, then `open .build/Sextant.app --args --import docs/research/oryx-examples/my-layout-KlgM7-40xJ7M.json` (the import writes to `~/Library/Application Support/Sextant/Library/`).

- **Ports and shared domain types** for Oryx, generator, toolchain, device watcher, keyboard link and flasher; adapter skeletons.
- **Tooling (ADR 0018):** pinned community packages; `scripts/check` runs swift-format, SwiftLint (quality + layer import rules), a warnings-as-errors build, tests and a Periphery report.
- **Security fix:** imported numbers could crash Sextant (`Int(Double)` traps); fixed and tested.

## In flight
- Workflow `mvp-slices` (run `wf_d18cfec3-579`, base `dc87917`): five slices in worktrees on branches `slice/build`, `slice/device`, `slice/oryx`, `slice/ui`, `slice/usecases`, each implemented, reviewed by three adversarial lenses, verified, fixed and re-verified. When it finishes: review each branch, merge in the order usecases → oryx → device → build → ui, wire the composition root (hardware gate, LiveSession, BuildFlashSession, ImportFromOryx), record ADRs for the slices' decisions, run an integration review.

**Merge blockers to verify before landing `slice/build`:**
- Security review (background, on `slice/build`): the generator emits layout data into C verbatim, so a hostile layout could inject C into `keymap.c`/`config.h`. Every data-derived token must be validated at the generator (catalogued keycode or strict `^[A-Z][A-Z0-9_]*$` identifier, serial limited to `[A-Za-z0-9/_-]`, animation ids from the settings catalog, finite integer numbers, no raw layout text in comments); otherwise throw `GeneratorError`. Needs hostile-input tests (closing parens, newlines, `#include`, `*/`).

## Next
1. Spec steps 4–7 (key inspector, picker and Record Key, layers, lighting), then 11–12 (firmware settings, Settings scene, empty states), then the import, device and Build & Flash UI over the merged use cases.

## Known gaps and notes
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
