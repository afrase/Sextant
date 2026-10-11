# 29. Layers and Lighting lens UI

Status: accepted, 2026-10-11

## Context
MVP steps 6 and 7 (spec §6.1, §6.2, §3.6–§3.8): layer management in the sidebar, Layer menu and layer summary, and the Lighting lens. `BoardView` takes the session plus presentation inputs (ADR 0025) and doesn't know the lens; its call site (`CanvasColumn`) belonged to another slice. A sidebar `List` row needs a context menu and double-click to rename in place. Colour pickers fire on every drag tick of the colour panel, and every `EditSession` edit is an undo step.

## Decision
- **The brush reaches the board through the environment.** `EnvironmentValues.brush` is set once at the window root (`LayerPresentations`, next to the window's alerts) and is nil outside the Lighting lens. With a brush, the board draws `LitKeyCap` (own colour at full strength, the layer colour at 35%, otherwise an unlit face with "off"; ink by luminance) and a board-level `DragGesture` replaces selection.
- **Every board gesture is gated on the lens.** The stroke is a `highPriorityGesture` on the framed board, enabled only with a brush. High priority does not stop a child's simultaneous gesture (a probe showed the key swap of ADR 0027 winning every drag), so the swap is gated itself: `swapsKeys` is on in the Keys lens only, and the Lighting lens draws lit caps without the select tap. A board gesture added later must be gated the same way.
- **One stroke, one undo step.** Keys crossed by a stroke (hit-tested on the key polygons) preview the brush from view state, and the stroke lands as one `EditSession.paint` ("Paint N Keys"). The eraser paints nil, so keys fall back to the layer colour. Clear Key Colours uses the same call.
- **Brush colour applies live; layer colour goes through a sheet.** The brush is window state, so its `ColorPicker` is bound directly. Custom… for a layer colour opens a small sheet whose picker edits a draft, so a drag in the colour panel makes one "Set Layer Colour" step, not dozens.
- **Rename in place with a row gesture.** Each row has its own `.contextMenu` and a `TapGesture(count: 2)` (off while editing, so the field gets word selection). `contextMenu(forSelectionType:primaryAction:)` was tried first: an offscreen probe showed it only works on the `List` itself, not on rows inside it, and that the row gesture leaves single-click selection intact. New Layer starts the rename at once. Layer ▸ Rename Layer… is disabled while the sidebar is hidden (Sextant never opens it, spec §2.2); the layer summary's name field still renames.
- **The selected row's index and badge use `.primary`**, because `.secondary` vanishes on the selected row's dark-mode fill.
- Pick, Fill Layer, the B/E/I/G keys, Esc cancelling a stroke, "Painted on" colour groups and the keyboard preview are out of scope (the preview is v1 and must not exist yet).

## Consequences
- `BoardView` changed in one branch only, and its board frame is the same in every lens.
- A reader of `BoardView` finds the brush through `@Environment(\.brush)`; the window, not the canvas, decides it.
- In offscreen snapshots, stock bordered controls inside `.inspector` render white in dark mode (verified with a probe: the same controls render correctly in the detail column and in `.content` scenes). It's a capture limitation, not product code; explicit tokens (not `.primary`) are used where an inspector shape must show.
