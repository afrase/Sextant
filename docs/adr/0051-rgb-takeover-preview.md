# 51. RGB takeover preview: claim, frames, release paths

Status: accepted, 2026-10-15. Builds on ADRs 0038 and 0057; amends spec §6.2.

## Context
The Lighting lens edits LED colors that reach the keyboard only by flashing. Oryx's module lets a host take the board's
lights over the live connection (research 03 §3.3): `05 01` takes them (reply `08 01`), `06 i r g b` sets one LED and
`09 r g b` sets all 52 (both also take the lights), and `05 00` gives them back, reloading the board's own lighting (reply
`08 00`). The firmware indexes its LED array with `i` unchecked, scales what the host sends by its own brightness, and
keeps the takeover in RAM: it lasts until a `05 00` from any host or a power cycle. While a host holds the lights, the
per-layer LED map doesn't show.

ADR 0038 built the channel (`KeyboardCommand.lighting`, `.setLED`, `.setAllLEDs`, clamped to the board's 52 keys) and
named the release paths; ADR 0057 made Live View something only the user starts. Two windows on two layouts could both
want the board, and the link writes one report per 5 ms, so 52 LEDs take about 260 ms.

## Decision
- **One rule for an LED's color.** `KeyboardLayout.ledColor(layer:index:)` (domain) is the key's own color, else the
  layer's, else nil (off). The generator's `ledmap` uses it, so the preview shows what a flash would; the goldens stay
  byte-identical.
- **A use case, app-wide.** `LightingPreview` (application) is built once in the composition root and shared through
  `SextantServices`. One window holds it at a time: `claim(for:title:)` is refused with a `LightingPreviewRefusal`
  (no keyboard, flash mode, Live View off, Keymapp, or "Previewing in <layout>" when another window holds it). The window
  gets the claim only from the user's switch: the Lighting inspector's "Preview on Keyboard" or Keyboard ▸ Preview
  Lighting on Keyboard. It is off at every launch and never turns itself on.
- **Frames.** The holding window feeds the shown layer's 52 colors whenever they, the layer or the brightness change, and
  only while it shows the Lighting lens on a layer's board. Everything goes through `LiveSession.send`, so nothing is
  written unless a Live View session is paired; each command is checked with `isAllowed(on:)` first, and indices are
  only ever 0–51 (a longer frame is cut, a shorter one padded with off). The first frame of a session sends `05 01`, then
  `09` with the frame's most common color, then `06` for each LED that differs. Later frames send `06` for each LED that
  changed, or fill again with `09` when that is fewer writes. After a batch the preview waits as long as the link takes
  to write it (5 ms a report) before sending the next, so frames that come faster coalesce and the latest wins per LED.
  Nothing else is ever sent: the command type can't express `07`, `08` or `0A`.
- **Brightness on the Mac.** A Brightness slider (10–100%, app-wide, not saved) scales r, g and b before they are sent.
  The keyboard's own brightness still scales them again.
- **Release.** `05 00` goes last, after anything queued, and only when the session was sent something:
  - the switch turned off; the window leaving the Lighting lens or its board (another lens, a page); opening another
    layout in the window; the window closing (and its feed task ending);
  - the Mac going to sleep (`NSWorkspace.willSleepNotification`, in the app delegate);
  - Live View turned off from the window: the release goes out and Live View stops after the keyboard's `08 00`;
  - quitting, once `Quitting` has decided to quit: the same wait.

  Those waits end on `08 00` or after 500 ms, since `IOHIDDeviceSetReport` has no timeout.
- **Without a session, nothing.** A session that ends (unplugged, Keymapp seizing, a failed write) is released without
  sending: there is no board to write to. The window's switch stays on, and when Live View pairs a session again, the
  whole frame goes out again, starting with `05 01`. Live View turned off by any other path ends the preview without a
  write too.
- **Another host's release.** Keymapp or Oryx in Chrome sending `05 00` gives the lights back too. Every `08 00` makes the
  preview forget what it sent, so its next frame takes them again in full (after Sextant's own release that costs at
  most one full resend). It never takes them back on its own.
- **Copy.** The section's footnote says nothing is saved until a flash, that the preview ends when the user leaves
  Lighting, and that it stays dark while the keyboard's lights are off (its own key, or Lights off when idle,
  `rgbTimeout`). The refusals are Sextant's own words; Live View off offers [Turn On Live View].

## Consequences
- Agents never send these commands to the user's Voyager. `LightingPreviewTests` run on `FakeKeyboardLink` and
  `FakeDeviceWatcher` with test clocks, `LightingPreviewWireTests` check the exact 32-byte reports through `RawHIDLink`
  on `FakeHID`, and `KeyboardLightingPreviewTests` drive the window's paths on a stand-in link. Trying the takeover on
  the keyboard needs the user's OK in chat for RGB takeover.
- If Sextant crashes, or the quit wait runs out, the colors stay until the keyboard is unplugged; the next launch sends
  nothing to repair them.
- Paired state is shared: Sextant's takeover hides Keymapp's or Oryx's, and either one's `05 00` ends Sextant's until its
  next frame.
- A frame stays at most one batch behind: after the first frame (about 260 ms of writes), a paint stroke's frames go out
  as they come, each a few writes.
- A firmware built without the RGB matrix answers with error `04`; the preview doesn't read it and just shows nothing.
