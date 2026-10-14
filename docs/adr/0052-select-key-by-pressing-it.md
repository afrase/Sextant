# 52. Select Key by Pressing It

Status: accepted, 2026-10-15. v1 plan slice 3.4. Builds on ADRs 0028 (Record Key's local monitor), 0037 (the lens
lane's pick capsule), 0038 (the press feed) and 0057 (Live View starts by hand); extends spec §13.2's local-monitor
exception.

## Context
Key ▸ Select Key by Pressing It (⇧⌘L, spec §9.1) selects the key the user presses on the keyboard, so a key can be
found on the board without reading the legends. The keyboard reports positions only over the live link, after pairing,
so it needs Live View on (ADR 0057). `LiveSession.activity()` delivers every key-down and key-up before the 60 Hz
coalescing, silent during secure input (ADR 0038).

The keyboard is also the Mac's keyboard: the same press reaches the window as an ordinary key event, just before or just
after the raw-HID report. Unchecked, it would open the picker (type-to-search) or, for Esc, deselect the key it just
selected. Only an `NSEvent` local monitor sees a key event before the board's key handling, and spec §13.2 allowed one
only during Record Key and Record Steps.

## Decision
- **One mode on the window.** `LayoutWindowModel.selectByPress` (`SelectByPress` in `Board/SelectByPress.swift`) is on
  from ⇧⌘L until the selected key's raw-HID key-up. Starting it ends Record Key and Record Steps and closes the palette or
  picker; any of those starting ends it. The first key-down from `activity()` selects that key on the shown layer, as a
  click does (on Combos, a combo it's in too), and VoiceOver hears "Selected key 24, Return, hold for Sym+Num". Later
  presses do nothing.
- **When it can start.** Only while the board shows (the layer board, Combos or History), no pick is under way, and a
  paired Live View session can report presses (`LiveSession.canSend`). Otherwise the menu item is disabled and its help
  tag says why: connect the keyboard, it's in flash mode, turn on Live View (Keyboard ▸ Live View), Keymapp holds it,
  Live View is still connecting, show the board, or finish choosing keys. The item never turns Live View on itself:
  pairing writes to the keyboard, and Live View starts only from its own controls (ADR 0057).
- **It ends** on esc, [Cancel], the window resigning key, and whenever it couldn't start now: the board hidden, a pick
  started, the session dropping (unplugged, Live View off, Keymapp). The model watches those with `Observations`, so the
  window's views aren't needed for it.
- **The Mac's copy of the press is swallowed.** Record Key's local monitor (`RecordKeyMonitor`) also runs while the mode
  is on, on the window's own events only, and swallows every key-down and modifier change until the mode ends. The
  layer shortcuts stand aside only for the recorders, as before (ADR 0048). Because the two copies of a press race, the
  mode ends 50 ms after the key-up rather than at it, so a fast tap's Mac copy is still swallowed.
- **Esc.** Esc from the Mac cancels, after the same 50 ms: if the keyboard reports a key-down meanwhile, that press was
  the keyboard's own Esc and is selected instead. Esc that reaches the board (the monitor installs only in the key
  window) is the first rung of the esc ladder, before a pick and the selection (spec §9.3).
- **Secure input pauses it.** The feed is silent then, checked at every event, so nothing is selected. The capsule says
  "Paused: secure input is on · esc cancels". Secure input turning on after a press, while waiting for its key-up, ends
  the mode, since that key-up never arrives.
- **The capsule** takes the pick's place in the lens lane: "Press a key on the keyboard… esc cancels" with [Cancel]. Like
  a pick's prompt it is the only place that says what the next press does, so it outranks an issue (spec §3.7).

## Consequences
- Sextant sends nothing new; it only reads presses from a session the user paired.
- With the Voyager as the only keyboard, esc can't cancel: every key, Esc included, is a press to select. [Cancel] and
  the window losing focus always work.
- While the mode is on, keys typed on the Mac in that window do nothing, ⌘ shortcuts included, as during Record Key.
- An esc from the Mac and a keyboard press inside the same 50 ms select the press.
- Tests run on a fake keyboard link and device watcher; the design-QA scenes `select-by-press` (light and dark) and
  `select-by-press-paused-min` (1120×640) use a stand-in keyboard paired on Sym+Num. No snapshot reference changed.
