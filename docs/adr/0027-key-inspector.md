# 27. Key inspector: drag to swap as a gesture, modifier holds, commit rules

Status: accepted, 2026-10-11

## Context
MVP step 4 (spec §5.1–§5.5) replaces the read-only key inspector with the key editor and adds drag to swap. Spec §13.2 names `.draggable` and `.dropDestination` for the swap. Spec §5.2 lets a hold press several modifiers ("`MT(MOD_LCTL|MOD_LSFT)`"), which Oryx's data has no single keycode for. Spec §13.3 item 5 asks for one undo step per edit, with text fields committing when editing ends.

## Decision
- **Drag to swap is one `DragGesture` on the board**, not system drag and drop. On macOS 26 a drop destination is an AppKit view that `ImageRenderer` draws as a placeholder, so it broke the board's reference images; a gesture also can't leave the window, so no payload has to be checked. It draws a dashed line from the dragged cap and an accent outline on the target (spec §4.7), but doesn't lift the source cap. ⌥ at release copies instead of swapping, read from `NSEvent.modifierFlags` (no event monitor). Each drop is one `EditSession.swapKeys` call: "Swap Keys" or "Copy Key". The gesture is on only in the Keys lens (`EnvironmentValues.swapsKeys`, set by the canvas), so a drag in the Lighting lens never moves keys.
- **Modifier holds:** a single modifier is its keycode (`KC_LEFT_ALT`), as Oryx stores it. Any other set, Hyper and Meh included, is the first modifier's keycode with the rest chorded (`KC_LEFT_CTRL` + Shift), which the generator already builds as a dual-function key or a tap-dance hold. Oryx's `ALL_T` and `MEH_T` would read better but don't build beside a non-basic tap or in a tap dance until `QMKCodes.statements` handles them. An `LM` key whose last modifier is turned off becomes `MO` on the same layer, because QMK can't build `LM(n,)`. `Legends.qmkExpression` now puts the chorded modifiers in the `MT` mask, so the QMK row shows `MT(MOD_LCTL | MOD_LSFT, KC_A)`. Turning the last modifier off clears the hold.
- **Commit rules:** the label commits on Return, when focus leaves, or when the key changes, and only if the text changed. An undo or menu edit of the label replaces the draft even while the field has focus. While the field has focus, Make Transparent (⌘⌫) and Disable Key (⇧⌘⌫) are off, so those keys edit the text. A colour from the colour panel waits 300 ms of quiet before it becomes one "Set Key Colour" step (the panel reports every step of a drag). Both views are keyed by layer id and key index and find the layer by id when they commit, so a selection change, layer move or layer deletion can't send the edit to another key.
- **Controls at 280 pt:** a layer key's behaviour (MO, TG, TO, TT, OSL, DF, plus LM on keys that already have it) and its target are pop-up menus, not a segmented control and chips: five segments don't fit the inspector's minimum width. A hold's layer is `MO` only, because the generator builds only `MO` and `TO` holds.
- **LED colour** is a stock `ColorPicker` plus No Colour. Key ▸ LED Colour lists No Colour and the layout's swatches.
- `KeyInspector` takes the window model, so its keycode tile, Change… and Hold ▸ Key can call `openKeycodePicker()`.

## Consequences
- Not built yet: the Record buttons (step 5), the swatch row and the "Off" colour, the per-key tapping term (v1) and multi-selection (v1).
- A label typed but not committed before ⌘Q is lost until the app ends editing before it flushes the open sessions.
- In the offscreen snapshot runner, controls inside an `.inspector` column draw wrongly: white in dark mode, and `.secondary` text drawn as primary in light. A probe with a stock `.inspector` showed the same. The dark inspector scenes need a check in the live app.
