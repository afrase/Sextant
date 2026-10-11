# 28. One floating panel for the palette and picker; positional Record Key

Status: accepted, 2026-10-11

## Context
Spec §5.6–§5.8 asks for a keycode picker (assign scope), a command palette (⌘K, general scope) and Record Key. The picker must float over the board without moving it (§3.3), preview the highlighted keycode on the target cap (§4.7), and Record Key must read the Mac's keyboard without Input Monitoring or other TCC prompts (§13.2). The board, cap and lens-lane files belong to other slices, so the hooks into them have to stay small.

## Decision
- **One panel, one state.** `Palette` (scope, query, category, highlight) lives on `LayoutWindowModel`; results are computed from it (`paletteItems`), so ranking, assigning and navigation are view-model logic tested without rendering. A view modifier on the canvas column hosts the panel as an overlay and puts the window model in the environment (`layoutWindow`), which is how the board's ⏎, type-to-search and the preview cap reach it without new `BoardView` parameters. Changing scope keeps the panel's identity, so the palette morphs into the picker.
- **Live preview without touching `KeyCap`.** `PickerCapOverlay` draws an opaque cap face, the previewed `KeyCap` at 75% and a dashed accent ring over the selected key; Record Key draws its pulsing red ring and REC badge the same way.
- **Keycodes come from the catalog as it is.** The rail is Suggested plus the catalog's 15 categories (System & Firmware is one; Transparent and Disabled sit in Layers); search is `KeycodeCatalog.search`. Layer functions are offered once per layer (`MO(1)`, `TG(2)`…). OSM, LM and RGB need a modifier or colour the picker can't ask for and are left out (`shortcut:`).
- **Assigning a plain HID keycode (`KC_…`) keeps the slot's chord modifiers**, as `EditSession.setCode` does; layer functions, quantum codes, Transparent and Disabled replace the action, since a chord would make them another keycode (`LSFT(QK_BOOT)` is `QK_KB_0`). No colour is carried over. It is one undo step through `EditSession.setAction`.
- **The target cap always stays visible.** `PickerCapOverlay` publishes the target's rotated bounds as an anchor preference, and the picker's frame is a function of that rect and the column: the opposite half at §5.6's width, narrowed to keep 8 pt clear of the key, because that width alone covers an inner thumb. Make Transparent and Disable Key are off while a panel is open, since ⌘⌫ in its field reaches the menu first.
- **Palette search** uses a small scorer (exact > prefix > word prefix > substring, every word must match) for commands, layers and keys; keycodes keep the catalog's ranking and settings use `SettingsCatalog.search`. A query that parses as an `OryxReference` *and* contains a "/" offers Import from Oryx first, so bare words are never mistaken for layout ids. Recents (keycodes and commands) are in memory, per window.
- **Record Key is positional.** A table maps macOS virtual keycodes (`kVK_*`, ANSI, ISO and JIS, written as literals because the UI layer may not import Carbon) to catalog keycodes; sides come from the device-dependent modifier bits. A local `NSEvent` monitor is installed only while recording and only acts on Sextant's key window; recording ends on esc, when that window resigns key, when another key is selected, or when the picker opens.
- **⇧⌘O** is a zero-size button in the window with that shortcut, since a menu item takes one key equivalent.

## Consequences
- The panel can't be captured with real glass offscreen; snapshots show `SurfaceStyle`'s opaque stand-in.
- Choosing a firmware setting in the palette only closes it until the Firmware Settings page exists (`shortcut:`); the palette has no Oryx preview pane (it would need a fetch the import sheet owns).
- Keys Sextant can't map (fn, unknown keycodes) keep recording going and say so in the lens lane.
