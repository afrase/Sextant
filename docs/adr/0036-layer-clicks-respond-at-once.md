# 36. Layer clicks respond at once: rename from the context menu, ease-out crossfade

Status: accepted, 2026-10-12. Supersedes ADR 0029's rename gesture.

## Context
The user found clicking a sidebar layer sluggish, even after the board's update was cut to about 41 ms, and asked for rename to be a right-click option, not a double-click. An offscreen probe hosted the real window with the user's layout and posted real mouse-down/up pairs into its own event queue. With an 80 ms click, the selection changed 447 ms after mouse-down, and the board's first frame committed at about 505 ms. SwiftUI's List selects on mouse-up through its own click recognizer. The row's `TapGesture(count: 2)` (ADR 0029) made that recognizer wait about 360 ms more for the double-click to fail, on every click but the window's first.

## Decision
- **No double-click on layer rows.** Rename… in the row's context menu starts the in-place rename, as do Layer ▸ Rename Layer… and New Layer. The field still takes focus, commits on Return and on losing focus, cancels on Escape, and selects a word on double-click (checked in the probe). The row keeps its full-width frame and content shape, because the badge's tooltip hit-tests: without them it covered only the name.
- **The caps' layer crossfade eases out** (`SextantMotion.layerChange`, still 0.18 s, the same under Reduce Motion). The first frame after a change shows the old board. Ease-in-out then moved it 7% in 33 ms and reached 25% at 62 ms; ease-out reaches 25% at 29 ms. The atmosphere stays linear over 0.3 s.

## Consequences
- With an 80 ms click, the selection changes about 2 ms after mouse-up (88 ms after mouse-down), and the board's first frame commits at about 145 ms instead of about 505 ms.
- Selection still waits for mouse-up; that is SwiftUI's List, not Sextant.
- The crossfade curve comes from SwiftUI's documented timing curves. An offscreen window gets no display-link frames, so it was not measured frame by frame.
