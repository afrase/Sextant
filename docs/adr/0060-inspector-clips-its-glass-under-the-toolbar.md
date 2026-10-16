# 60. The inspector clips its glass below the toolbar, showing AppKit's own band

Status: accepted, 2026-10-16. Supersedes ADR 0059.

## Context
ADR 0059 painted a band over the inspector's top: an `NSVisualEffectView` with the window's `contentBackground` material
and a separator hairline. In the app the band came out darker than the canvas's (the user's screenshots, 2026-10-16:
`#2D2F31` over the inspector against `#37393A` over the canvas, in dark mode). The effect view sat inside the
inspector's full-height glass panel and blended with the glass under it.

A probe in the real, on-screen window dumped the view and layer tree (offscreen rendering draws neither glass nor the
toolbar band, so it can't show this). From the first frame, AppKit already gives the inspector's column its own
`NSTitlebarBackgroundView` and `NSScrollPocket`. Their layers match the canvas column's exactly: the same blur, the same
82% tint and the same 0.5 pt hairline. They sit below the inspector's `_NSSplitViewItemViewWrapper`, whose
`NSGlassEffectView` runs the full height of the window and covers them. Moving the divider in code or resizing the
window programmatically changes none of this. Only the user's own drag did, which is why every attempt to trigger the
layout failed.

## Decision
The inspector clips its glass panel instead of painting over it. A view behind the inspector's content finds its
`NSGlassEffectView` ancestor and gives that layer a mask covering everything below the toolbar's bottom edge
(`contentLayoutRect.maxY`) and the hairline's pixel under it. AppKit's own band then shows through: the same views that
draw the canvas column's band, in every appearance. The mask follows the inspector's size (`layout()`) and the
toolbar's edge (KVO on `contentLayoutRect`, so Hide Toolbar moves it up to the title bar) and the panel's own frame
(which animates in while the inspector's content keeps its size). It clears itself when there is nothing to clip, when
the content leaves its window or moves to another panel, and it leaves the glass alone if AppKit ever gives it a mask of
its own.

While a window opens, AppKit rebuilds the inspector's column up to three times and moves the content between new glass
panels, and a panel gets its layer only after the content has arrived. So the view checks again whenever it moves to a
new superview, and when the panel has no layer yet it retries on the next turns of the run loop (at most ten). Without
that, about one launch in four (5 of 18 in the probe) started with no mask; with it, 12 of 12 did.

## Consequences
- The band and hairline are AppKit's in both columns, so they match from the first frame. The real window confirms the
  mask through launches, resizes, the inspector turned off and on, Hide Toolbar, and full screen (where the toolbar
  moves into its own window with its own band per column; the mask follows its edge, and with the toolbar hidden there
  the panel stays full height, as the sidebar does). Its look on screen is the user's to confirm, since nothing here
  can capture glass without a screen-recording prompt.
- It leans on undocumented AppKit behavior: that the column's band is drawn beneath the glass, and that AppKit leaves
  the glass layer's mask alone (if it resets it, the mask returns at the next layout). Finding the panel needs only the
  nearest `NSGlassEffectView` ancestor, a public class. If a later macOS lays the inspector out below the toolbar, the
  cut shrinks to the hairline's pixel and no mask is set; if the band moves out from under the glass, the clipped top
  would show whatever is behind, and this should be revisited.
- Content scrolled up under the toolbar is clipped by the mask, as a hard scroll edge would.
