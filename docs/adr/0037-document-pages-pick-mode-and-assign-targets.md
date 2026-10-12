# 37. Document pages, board pick mode and assign targets

Status: accepted, 2026-10-12. Amends ADR 0028: the picker writes to a target, not only the selected slot.

## Context
v1 adds four document pages next to Firmware Settings (spec §2.2: Combos, Macros, History, App Layers). It adds two gestures that take board clicks: Assign to Key (§6.3) and choosing a combo's members (§6.4). It also adds picker targets that aren't a key's slot: "Combo 3 › Output", macro steps, multi-selection. In the MVP the destination was a Bool, `showsFirmwareSettings` (26 uses in 10 files). The picker could write only the selected key's slot (ADR 0028), and every board click selected. Without shared hooks, every feature slice would edit the same sidebar, detail, inspector, picker and board code (v1 plan, wave 0).

## Decision
- **`destination: Destination` replaces the Bool.** `Destination` declares every v1 page now: `.layer(Int)`, `.firmwareSettings`, `.combos`, `.macros`, `.history` and `.appLayers`.
  - A layer is the session's selected layer, so Follow and undo keep moving it. The model stores only `page` (nil on the board) and derives `.layer(n)`.
  - WindowDetail reads `page`, so a layer switch still doesn't re-run it.
  - The unbuilt pages route to `EmptyView` in WindowDetail and InspectorColumn and have no sidebar row, so nothing reaches them. Each feature adds its row and replaces its one route line.
- **Combos and Changes are board modes of their destinations, not `Lens` cases.** `Lens.allCases` drives View ▸ Lens (⌃⌘n), the canvas picker and the palette, and spec §9.1 lists only Keys, Lighting and Heatmap.
- **`BoardPick` is a gesture in progress:** a prompt, `onPick(index) -> Bool` and `onCancel`, on the window model.
  - While one is set, board clicks and VoiceOver's activate go to it instead of selecting. Painting and drag-to-swap are off. `true` from `onPick` ends it.
  - Its prompt takes the lens lane's status capsule, with [Cancel], ahead of an issue and recording. It is the only place that says what a click does.
  - Esc on the board cancels it before deselecting (§9.3 step 4, then step 5).
  - Opening another layout drops it.
- **`AssignTarget` is what the picker writes to:** the scope token's text, an optional key to show and preview, the current value, and an assign closure.
  - `Palette.target` holds a feature's target. Nil means the selected key's slot, which is today's behavior. It is built live from the selection, so ⌘⏎, ⌥⇥ and a click on another key still retarget it.
  - A feature's target works on any page. ⌘⏎ assigns and closes (there is no next key), ⌥⇥ does nothing, and a click on a key closes the panel like any click outside. Dropping the token drops the target.
  - Opening another layout closes the panel, since a target's closure edits the layout it was made for.
- **NavigatorDisc moves to its own file** for Export, LayerMap and the HUD.

## Consequences
- Features add files plus one-line hooks: a sidebar row, one route line each in WindowDetail and InspectorColumn, and a `BoardPick` or `AssignTarget` value. Combos and Macros never edit BoardView's click code or the picker's assign path.
- The general palette offers "Assign to …" keycode rows only where the key is shown. On a page they used to do nothing.
- In the Lighting lens a pick shows plain caps, since lit caps take no clicks.
- A destination change doesn't end a pick. Assign to Key starts on the Macros page and switches to the board, so the feature that makes a pick ends it.
- Window snapshots are pixel-identical.
