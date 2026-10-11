# 31. Device and Build & Flash in the window

Status: accepted, 2026-10-11

## Context
MVP steps 9 and 10 put `LiveSession` (app-wide) and `BuildFlashSession` (one per open layout) in front of the user: the
activity capsule, the sidebar device card, the Device popover, Follow, live presses and the Build & Flash sheet (spec
§3.5, §3.6, §7, §8.2). The window skeleton had stand-ins: a stored `activity`, a stored `isFollowing` and an `onBuild`
hook. Parallel UI slices own the layer controls (sidebar, ⌘1–9, the jump menu), so this slice can't hook each of them.

## Decision
- **One source of truth each.** With a live session, `LayoutWindowModel.activity` is derived on read from the live
  session, the serial match and the Build & Flash phase (a run first, then live issues, then the keyboard). `isFollowing`
  reads and writes `LiveSession`'s Follow, so Follow is app-wide. It counts only while a layer arrives: with live access
  off (today's default) or Keymapp holding the keyboard, Follow is on in the use case, but nothing says "LIVE". Without
  a live session (tests, snapshots) both keep a settable stand-in, so existing scenes still draw fixed states.
- **Follow by observation.** One loop per window (`followKeyboard()`, an `Observations` sequence) shows the followed
  layer, feeds presses into `PressedKeys`, and stops following when the shown layer changes for any other reason. Any
  hand-picked layer counts (sidebar, ⌘1–9, the jump menu, Show Key), and no layer control has to know about Follow.
- **The serial match uses the build's rule.** `BuildFlashSession.importedLayout()` (new, tested) gives the window the
  same import revision a build compares against, so the capsule's "On keyboard" and the build's serial agree (ADR 0019).
  The count of edits shows only when the keyboard runs that import's Oryx build. Otherwise Sextant can't count them.
- **Build & Flash per window.** `makeBuildFlash` makes one per opened layout. It is stopped when the window switches
  layout or closes. A flash that can't be stopped (from validation until the keyboard comes back, at most 10 s after
  writing) keeps the window on its layout, so its progress stays in view. ⌘R brings up the sheet and ⌘B builds quietly
  (the capsule shows progress). Hide only dismisses.
  A finished flash shows "Flashed" in the capsule for 8 s, then gives way to the keyboard's status. A flash that
  couldn't be recorded in History keeps saying so until the sheet shows why.
- **One flash at a time, app-wide (spec §7.6).** `LiveSession` holds the one layout whose Build & Flash waits for flash
  mode or flashes (`claimFlashMode(for:)`, `releaseFlashMode(for:)`). `BuildFlashSession` claims it before it waits
  for flash mode and lets go when that step ends (done, failed or stopped). A second run that reaches the step meanwhile
  fails with `flashingElsewhere` and never looks for the bootloader. Other windows disable Build, Build & Flash, Flash…
  and Try Again, and their capsule says "Flashing from ‘<layout>’". The live session holds it because it is already the
  one app-wide object for the keyboard, so no new service is wired.
- **Follow only means this layout's layers.** When the keyboard runs another layout, its layer numbers mean other
  layers: the shown layer doesn't move, the sidebar has no live badge, and the lane says "LIVE · Layer 2".
- **The UI only reports.** The sheet maps every `BuildFlashSession.Phase` to the spec's copy and buttons. There is no
  "Flash Now", and Cancel is disabled from validation on. "Download and Build" stays disabled until the user approves
  the toolchain download. "Flash Oryx's Build" stays disabled because the use case can't flash a stored image yet.
- **Honest copy where the use case differs from the spec.** The verify step waits for the keyboard to come back with
  the build's serial, so it shows no percentage and says so. The DFU flasher doesn't read back, so the footer says
  "checks the image first", not "verifies every byte".
- **Smaller than the spec, for now.** The size meter is one bar, since the build reports no per-feature breakdown. Card
  B lists numbered steps with the real keys as mini caps, not a rendered board close-up. The popover shows key
  positions (`k13`), never letters, and has no event monitor yet. The device card shows only where a live session exists.

## Consequences
- Every window shows the same keyboard and Follow state; building and flashing stay per layout.
- Undo or Add Layer changing the shown layer also stops Follow. That is consistent with "a layer chosen by hand".
- Two windows can't race to write different layouts to the same bootloader. Two builds may still run at once; only
  the first to reach flash mode goes on.
- Show Details gives the DFU status and address but not the step, because the flasher doesn't report the step with
  its error.
