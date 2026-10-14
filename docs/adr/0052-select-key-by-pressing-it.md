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
  click does (on Combos, a combo it's in too), and VoiceOver hears "Selected key 24, Return, hold for Sym+Num", read
  from the board as shown (on History, the revision's layer). Later presses do nothing.
- **⇧⌘L typed on the keyboard isn't the press.** The menu runs on the Mac's copy of L, and the keyboard's report of the
  same L can come after it, into the stream just subscribed. So a key-down within 50 ms of the start, or while any key
  held at the start (the session's held keys then: the shortcut's ⇧ and ⌘) is still down, is skipped. A key held at
  the start that the held keys, a frame late, no longer show doesn't count.
- **When it can start.** Only while the board shows (the layer board, Combos or History), no pick is under way, and a
  paired Live View session can report presses (`LiveSession.canSend`). Otherwise the menu item is disabled and its help
  tag says why: connect the keyboard, it's in flash mode, turn on Live View (Keyboard ▸ Live View), Keymapp holds it,
  Live View is still connecting, show the board, or finish choosing keys. The item never turns Live View on itself:
  pairing writes to the keyboard, and Live View starts only from its own controls (ADR 0057).
- **It ends** on esc, [Cancel], the window resigning key, and whenever it couldn't start now: the board hidden, a pick
  started, the session dropping (unplugged, Live View off, Keymapp). The model watches those with `Observations`, so the
  window's views aren't needed for it. VoiceOver hears "Stopped selecting a key by pressing it." when it ends before a
  press, since the capsule just goes.
- **The Mac's copy of the press is swallowed.** Record Key's local monitor (`RecordKeyMonitor`) also runs while the mode
  is on, on the window's own events only, and swallows every key-down and modifier change until the mode ends. The
  layer shortcuts stand aside for it as they do for the recorders (ADR 0048): a press that selects must not also move
  the keyboard's layer. Because the two copies of a press race, the mode ends 50 ms after the key-up rather than at it,
  so a fast tap's Mac copy is still swallowed. For a key the tapping term times (a hold, a double tap, a tap then hold),
  read from the open layout on the layer the keyboard reported, it ends a tapping term and 50 ms after: a tap dance
  sends its tap only once the term passes without another tap. Over-waiting for a mod-tap only swallows Mac keys a
  moment longer.
- **The key-up is never lost for good.** The feed checks secure input at every event, but the flag the session shows is
  polled once a second, so a key-up dropped by a short spell of secure input would leave the mode waiting, the window
  swallowing every key with no capsule. The feed keeps keys paired instead (ADR 0050): when secure input hides an event
  or the session ends, it sends the key-up of every key it reported down, so the selected key's key-up always comes.
  The session's held keys don't end the mode: a stale secure-input flag empties them while the key is still down. (A
  first version watched them, and ended the mode a moment after the press, the key still held.) And an esc from the Mac while waiting for the key-up
  ends it, unless it comes within 50 ms of the press (the press's own copy; the monitor drops its repeats). The
  secure-input flag itself no longer ends the mode: just after secure input goes off it is still on, and ending then
  would let the press's Mac copy through.
- **Esc.** Esc from the Mac cancels, after the same 50 ms: if the keyboard reports a key-down meanwhile, that press was
  the keyboard's own Esc and is selected instead. While the monitor runs no key event reaches the board, so the esc
  ladder's first rung (spec §9.3), before a pick and the selection, serves only an exit command that comes without one,
  as in the moment before the monitor installs; it ends the mode at once.
- **Secure input pauses it.** The feed is silent then, checked at every event, so nothing is selected. The capsule says
  "Paused: secure input is on · esc cancels", true then since the keyboard's Esc isn't reported either. VoiceOver hears
  the capsule's text when the mode starts, pauses and resumes.
- **The capsule** takes the pick's place in the lens lane: "Press a key on the keyboard to select it" with [Cancel]. It
  doesn't promise esc: with the keyboard as the Mac's only one, its Esc is a press to select. Like a pick's prompt it is
  the only place that says what the next press does, so it outranks an issue (spec §3.7).

## Consequences
- Sextant sends nothing new; it only reads presses from a session the user paired. A test counts the fake link's
  commands: none.
- With the Voyager as the only keyboard, esc can't cancel: every key, Esc included, is a press to select. [Cancel] and
  the window losing focus always work.
- While the mode is on, keys typed on the Mac in that window do nothing, ⌘ shortcuts included, as during Record Key.
- An esc from the Mac and a keyboard press inside the same 50 ms select the press.
- A press within 50 ms of ⇧⌘L, or while a key held at ⇧⌘L is still down, isn't selected.
- The tapping-term tail reads the open layout, which may not be what the keyboard runs; a keyboard on another layout
  gets the plain 50 ms tail when the reported layer doesn't exist here.
- Tests run on a fake keyboard link and device watcher; the design-QA scenes `select-by-press` (light and dark) and
  `select-by-press-paused-min` (1120×640) use a stand-in keyboard paired on Sym+Num. No snapshot reference changed.
