# 62. Overlay placement, opacity, delay and a preview

Status: accepted, 2026-10-16. Amends ADRs 0045 (the overlay settings) and 0050 (the HUD) and spec §8.4.

## Context
The user asked to customize the overlay HUD: "opacity settings, delay and position on screen". It could sit at the bottom
or top centre, 72 pt from the edge, on the screen with the pointer, fully opaque, after a 0–500 ms delay. Tuning it meant
holding a layer key with Live View on. Offered nine spots plus a margin and a display, or dragging it anywhere, the user
chose the nine spots.

## Decision
- **Position:** nine anchors (corners, edge midpoints, centre). The stored `bottom` and `top` keep meaning bottom centre and
  top centre, so existing settings carry over. Settings › Keyboard draws them as a 3×3 picker on a small screen; each target
  is a button VoiceOver names.
- **Distance from edge:** 0–200 pt (72, the old fixed value), from the anchored edges of the visible frame. The panel is
  always kept inside the visible frame.
- **Display:** the one with the pointer when the overlay appears (as before; "Follows the pointer"), or the main display
  (the one with the menu bar; "Main display"). Not the display with focus: the overlay shows over other apps, whose key
  window Sextant can't see.
- **Opacity:** 30–100% in 5% steps (100%), the whole panel, the reminder pill included.
- **Delay:** 0–1000 ms (was 0–500), still 150 ms by default.
- **Entrance:** rises 8 pt into place, except in the top row, where it drops 8 pt into place; a plain fade under Reduce
  Motion, as before.
- **Preview:** a button at the top of the pane's overlay options shows the full overlay with the current settings, even with Live View off: the
  keyboard's layout on its layer 1 when Sextant has it, else a sample. Its header says "Preview". Every change re-places it at
  once. It ends when clicked again, when the pane closes, or 8 s after the last change. A real presentation wins over it.
- The keys and defaults are declared twice, in the pane and in `OverlaySettings` (ADR 0045's rule).

## Consequences
- The HUD can now cover what the user is working on (the centre, a low opacity); that's their call, and it still never takes
  focus or clicks.
- Dragging the overlay to an arbitrary spot isn't offered; a margin and nine anchors cover the places users asked for.
