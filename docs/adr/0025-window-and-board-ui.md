# 25. Window minimums and board rendering choices

Status: accepted, 2026-10-11

## Context
Spec §3.2 gives column minimums (sidebar 200, inspector 280, centre 640) and ideals (228, 300). Spec §13.3 item 6 asks that a key press not redraw the whole board.

## Decision
- The honest minimum is a window-level frame: 640, plus 200 with the sidebar, plus 280 with the inspector. Column ideals equal their minimums (200 and 280, not 228 and 300): on macOS 26 a detail-column `minWidth` makes NavigationSplitView count the sidebar twice, and the spec's ideals left the centre 592 pt at the honest 1120 minimum. Default caps are about 55 pt rather than 52.
- `BoardView` takes the `EditSession` plus presentation inputs (legend mode, issue map, `PressedKeys`, highlighted kind, grid); there is no separate board view model.
- `PressedKeys` holds one observable state per key and `KeyCap` is an `Equatable` view, so a press redraws one cap.
- The selection ring is one board-level overlay animating between key frames.
- Board reference images use swift-snapshot-testing through `ImageRenderer` (no window, no TCC); they are machine-specific and re-recorded on a new macOS build.

## Consequences
- Deviates from spec §3.2's ideal widths and §3.3's typical 52 pt cap, in exchange for no clipping at the minimum window.
