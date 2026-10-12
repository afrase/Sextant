# 37. Document pages, board pick mode and assign targets

Status: accepted, 2026-10-12. Amends ADR 0028: the picker writes to a target, not only the selected slot.

## Context
v1 adds four document pages next to Firmware Settings (spec §2.2: Combos, Macros, History, App Layers). It adds two gestures that take board clicks: Assign to Key (§6.3) and choosing a combo's members (§6.4). It also adds picker targets that aren't a key's slot: "Combo 3 › Output", macro steps, multi-selection. In the MVP the destination was a Bool, `showsFirmwareSettings` (26 uses in 10 files). The picker could write only the selected key's slot (ADR 0028), and every board click selected. Without shared hooks, every feature slice would edit the same sidebar, detail, inspector, picker and board code (v1 plan, wave 0).

## Decision
- **`destination: Destination` replaces the Bool.** `Destination` declares every v1 page now: `.layer(Int)`, `.firmwareSettings`, `.combos`, `.macros`, `.history` and `.appLayers`.
  - A layer is the session's selected layer, so Follow and undo keep moving it. The model stores only `page` (nil on the board) and derives `.layer(n)`.
  - WindowDetail reads `page`, so a layer switch still doesn't re-run it.
  - Combos and History show the board (§2.2), so changing the layer there keeps the page. A layer picked by hand and the layer commands leave only the pages that replace the board. Choosing a layer as the destination (sidebar, ⌘1–9, ⌘K's layer rows, Find Key) always shows its plain board.
  - The unbuilt pages route to `EmptyView` in WindowDetail and InspectorColumn and have no sidebar row, so nothing reaches them. Each feature adds its row and replaces its one route line.
- **Combos and Changes are board modes of their destinations, not `Lens` cases.** `Lens.allCases` drives View ▸ Lens (⌃⌘n), the canvas picker and the palette, and spec §9.1 lists only Keys, Lighting and Heatmap.
- **`BoardPick` is a gesture in progress:** a prompt, `onPick(index) -> Bool` and `onCancel`, on the window model.
  - While one is set, board clicks, VoiceOver's activate and ⏎ on the focused board go to it instead of selecting, so the keyboard alone can pick (arrows, then ⏎). Typing and ⌫ do nothing, and painting and drag-to-swap are off. `true` from `onPick` ends it.
  - Starting one, or showing the board while one is on, focuses the board, so ⏎ and esc work at once.
  - Its prompt takes the lens lane's status capsule, with [Cancel], ahead of an issue. It is the only place that says what a click does. Record Key started during a pick hides it until recording ends, since esc ends recording first (§9.3 step 1).
  - Esc on the board cancels it before deselecting (§9.3 step 4, then step 5).
  - Opening another layout cancels it, so its `onCancel` runs.
  - The selected key's picker can still open during a pick (Key ▸ Change Keycode…), but a click on a key closes it and goes to the pick instead of retargeting.
- **`AssignTarget` is what the picker writes to:** the scope token's text, an optional key to show and preview, the current value, and an assign closure.
  - `Palette.target` holds a feature's target. Nil means the selected key's slot, which is today's behavior. It is built live from the selection, so ⌘⏎, ⌥⇥ and a click on another key still retarget it.
  - A feature's target works on any page. ⌘⏎ assigns and closes (there is no next key), ⌥⇥ does nothing, and a click on a key closes the panel like any click outside. The footer leaves out "& next" and ⇧⌘R. Dropping the token drops the target.
  - The board previews a target's key only on the shown layer, with the keycode as `assign` receives it: only the selected slot keeps its chord.
  - Opening another layout closes the panel, since a target's closure edits the layout it was made for.
- **NavigatorDisc moves to its own file** for Export, LayerMap and the HUD.

## Consequences
- Features add files plus one-line hooks: a sidebar row, one route line each in WindowDetail and InspectorColumn, and a `BoardPick` or `AssignTarget` value. Combos and Macros never edit BoardView's click code or the picker's assign path.
- The general palette offers "Assign to …" keycode rows only where the key is shown. On a page they used to do nothing.
- In the Lighting lens a pick shows plain caps, since lit caps take no clicks.
- Multi-select's "3 keys › Tap on Main" is the default target, not a feature's: slice 2.2 replaces `keySlotTarget`, the one picker function it edits, so ⏎, typing, ⌥⇥, ⌘⏎ and click-to-retarget keep working for it.
- A destination change doesn't end a pick. Assign to Key starts on the Macros page and switches to the board, so the feature that makes a pick ends it.
- Window snapshots are pixel-identical.
