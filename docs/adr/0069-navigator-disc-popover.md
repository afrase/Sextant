# 69. The board's Navigator disc opens a popover

Status: accepted, 2026-11-14. The user's request.

## Context
Spec §4.1 drew the Navigator as a recessed, non-interactive disc whose tooltip pointed at Firmware Settings › Navigator. With the trackpad driver (ADR 0068) the Navigator's settings live in two places: Sextant's Settings › Navigator, which applies on this Mac to every layout at once, and the layout's Firmware Settings › Navigator, which changes only after Build & Flash. The user clicked the disc and expected its settings. The disc is the obvious place to click, and it did nothing.

## Decision
- **Clicking the disc on the editing board opens a popover.** It is a button there, with a hover state and the label "Navigator settings". It stays drawn-only on a read-only board (Changes, a revision), during a board pick, in the layer map and in exported images.
- **The popover has two halves, named for where the setting lives:**
  - **On this Mac** (a trackpad only): the driver's switch and status, the settings reached for most (tracking speed when it isn't following the Mac, pad rotation, tap to click, tap-then-drag), and **More in Settings…**, which opens Settings on the Navigator pane. A missing permission shows as one line with **Allow in Settings…**; the permission rows themselves stay in Settings.
  - **On the keyboard:** the Navigator's kind and side, a note that changes apply after Build & Flash, and **Firmware Settings…**, which opens that page at its Navigator section with any filter cleared.
- **It is not a second Settings window.** Every control in it also exists in Settings › Navigator and edits the same `TrackpadDriver`; the full set stays there.
- **Settings remembers its pane** (`settingsPane`), so another window can open it on one.
- **Every slider in Settings › Navigator has a number field** beside it (the user: the sliders are hard to set exactly). A typed value is held to the range but not to the slider's steps.

## Consequences
- Spec §4.1's "non-interactive" is replaced for the editing board.
- The popover and Settings › Navigator have offscreen snapshot scenes over stand-in ports (`settings-navigator`, `navigator-popover-*`).
- The board's keyboard-focus outline no longer flashes when the board is clicked: focus arrives at mouse-down, before the tap that marked it as a pointer focus ended.
