# 59. The inspector draws the toolbar band over its own top

Status: accepted, 2026-10-15. Closes the "toolbar band" known gap (progress.md).

## Context
The detail column shows a band under the toolbar: the window's content background (above the canvas, which stays in the
safe area) and the titlebar's hairline. On macOS 26 the inspector, nested in the detail column, first lays out as a
full-height glass panel (an `NSGlassEffectView` around the item) running up behind the toolbar, and the titlebar leaves
its hairline out over a full-height column. So the band stopped at the inspector's edge, and the panel's gray showed
behind the toolbar's buttons. After a drag of the divider AppKit lays the inspector out below the toolbar, and the band
runs across the window: the look the user wants (their screenshots, 2026-10-15: the inspector body is the same gray in
both; the only difference is a near-white band and a 0.5 pt hairline over it).

What doesn't make AppKit choose that layout from the start (offscreen and in an on-screen test window): moving the
divider in code, collapsing and expanding the inspector, resizing the window, `allowsFullHeightLayout = false` on the
inspector's split item (with and without those), a hard scroll edge on the inspector's scroll view, `.inspector` on the
split view, and an ideal width above the minimum. A divider nudge did work in the app, but collapsed the inspector when
it was reopened, and no public API names the switch.

## Decision
The inspector column draws the band itself, as an overlay over its top: the toolbar's height (its top safe-area inset)
of `NSVisualEffectView` with the window's own material (`contentBackground`, within the window, active), which is what
shows in the detail column, and a hairline of `separatorColor` one pixel high, where the titlebar draws its own. It
ignores hits and VoiceOver. When the inspector already starts below the toolbar (top inset 0) it draws nothing, so the
system's band and this one never stack. As an overlay it also hides inspector content scrolled up under the toolbar,
as a hard scroll edge would.

## Consequences
- The band and hairline run straight across the window from the first frame, in light and dark (checked offscreen; the
  glass itself can't be rendered there, so the final look is the user's to confirm in the app).
- If a later macOS stops laying the inspector out full height, the overlay draws nothing and the system's band shows.
- The hairline's shade over the glass may differ slightly from the titlebar's over the canvas: both are the separator
  color over what lies beneath.
