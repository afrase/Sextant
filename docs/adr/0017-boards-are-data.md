# 17. Boards are data: everything board-specific comes from `BoardDefinition`

Status: accepted, 2026-10-11

## Context
Sextant ships for the ZSA Voyager, but supporting more keyboards is a stated future goal (the user, 2026-10-11), and their physical layouts differ: key count, stagger, thumb clusters, split or not, Navigator or not. Research 00 §8 recommends a board-agnostic model with Voyager-only features until v1. The first milestone review found the codec accepting a non-Voyager layout and the board view then crashing, because the view assumed 52 keys.

## Decision
- A layout names its board with `geometry` (Oryx's name). `BoardDefinition.named(_:)` looks it up in `BoardDefinition.all`; an unknown board is refused at decode time (`OryxDecodingError.unsupportedBoard`), never half-loaded.
- `BoardDefinition` owns every board fact: key count, matrix, LED map, `LAYOUT` order, USB ids, bootloaders, flash window, raw-HID usage, and the key shapes (`geometry(navigator:)`). Nothing outside it hard-codes 52, the PIDs or addresses.
- The UI fits whatever geometry it gets: the spec's cap formula uses the board's own size in pitch units instead of the Voyager's 15 × 6.7, and board-specific furniture (the Navigator disc, flash-mode instructions) is drawn only when the definition or layout has it.
- Ports take a `BoardDefinition` where the board matters (toolchain, device watcher, live link, flasher). Firmware families are adapters: the QMK generator with ZSA modules and the DFU flasher serve ZSA boards; another family (Vial, UF2) would be another adapter behind the same ports.

## Consequences
- A ZSA sibling (Moonlander, Ergodox EZ) is mostly a new definition plus its geometry builder; a Corne also needs its own generator and flasher adapters and per-half flashing.
- `BoardDefinition.geometry(navigator:)` is still the Voyager builder (shortcut, marked in code) until a second board exists.
- Not built: choosing a board for a new layout, or any second board's data.
