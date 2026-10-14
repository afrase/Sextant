# 53. Heatmap recording and storage

Status: accepted, 2026-10-15. v1 plan slice 4.1. Builds on ADRs 0038 (the activity feed), 0039 (OnKeyboard), 0045 (the
retention default), 0050 (the feed's paired keys and secure-input markers) and 0057 (Live View starts by hand). Amends
ADR 0023's "nothing stored", and spec §8.3, §8.5 and §8.9.

## Context
Spec §8.5 adds a Heatmap lens: each cap filled by how often it is pressed, with statistics, over 24 hours, 7 days, 30
days or everything kept. That needs presses counted over days and weeks, so something about typing has to be written to
disk. Until now nothing was: ADR 0023 keeps live events in memory, ADR 0045 keeps the raw-HID log in memory, and
Settings › Privacy promised that key events are never written.

The keyboard reports matrix positions, never characters (ADR 0038), but positions in order, with their timing, read
against the layout give back what was typed, passwords included. Presses arrive only from a paired Live View session,
which the user starts by hand (ADR 0057), and `activity()` is silent during secure input, checked at every event (ADR
0050).

## Decision
- **Opt-in.** Settings › Privacy › "Record a heatmap of key presses" is off by default. The lens's Turn On… asks first,
  saying what is kept. `HeatmapRecorder` (application, app-wide, on `SextantServices`) holds the choice and the retention;
  the composition root reads and saves them (`PrivacySettings.recordsHeatmap()`, `saveHeatmap`), so the application
  layer never reads UserDefaults.
- **What is counted.** Only key-downs from `LiveSession.activity()`, each on the layer the keyboard reported as it went
  down (`LiveActivity.keyDown`'s layer), plus the keyboard's moves between layers (not the layer a pairing first
  reports). Only while recording is on, over a paired Live View session, and only when `OnKeyboard` resolves the
  keyboard's firmware to a library layout: counts are keyed by that layout's id and by the layer's id (`Layer.id`) in
  the flashed revision, so reordering layers keeps their counts. Nothing is counted during secure input: the feed
  delivers no press or layer then, so a layer reached meanwhile isn't counted as a move either. `status` says why
  nothing is counted (off, no keyboard, flash mode, Live View off, Keymapp, another layout, secure input).
- **What is stored: hourly counts, nothing finer.** Per layout and hour: presses by layer id and key index, and moves
  onto each layer. Never the order of keys, a time finer than the hour, or characters. The menu bar's words per minute
  comes from the last minute's press times, kept in memory only and never written.
- **Where.** `~/Library/Application Support/Sextant/Heatmap/<layout id>/<yyyy-MM-dd>.json`, one file per UTC day
  (`HeatmapFiles` in SextantStorage, behind the `HeatmapStore` port). Outside the `.sextant` packages, so layout exports,
  Duplicate, revisions, the content hash and the `sx-` fingerprint never carry typing data. Each write replaces a whole
  file atomically; a damaged file, or one from a newer Sextant, reads as empty and the next write for its day replaces it.
- **When.** Every 60 seconds on the injected clock, when recording is turned off, and at quit, once quitting is decided.
  A write that fails keeps its counts for the next one.
- **Retention.** 30 days by default (ADR 0045), or 90 days or a year. Older hours are pruned at launch, when the setting
  changes, and at the first write of each day.
- **Clearing.** Clear Heatmap Data… in Settings › Privacy clears every layout's counts; the inspector's clears the open
  layout's. Both ask first. A layout that leaves the library and whose package is gone (Move to Trash) loses its counts;
  one that only fails to read for now keeps them.
- **Windows read** a layout's stored hours through the recorder, never during a write, and add what was counted since:
  the writes after the version they read, then what isn't written yet. So the board's heat follows typing, and a press
  is never counted twice or lost while a write lands.
- **The lens.** `Lens.heatmap` (⌃⌘3 from `Lens.allCases`). Caps take the single-hue ramp (spec §10.1), interpolated in
  OKLab and kept as 21 shared tokens, on a log scale against the layer's busiest key, with the count under the legend
  ("22k") and in VoiceOver ("22,044 presses"); a layer with no presses in the range draws plain caps. Legend ink is black
  or white by luminance, which reads at 4.5:1 on every step. The lens lane says "170,867 presses · 7 days · Main 88%" or
  why nothing is counted, with Turn On… or Turn On Live View; the strip shows each layer's share, or with a key
  selected its presses on each layer. The inspector has the range, the recording status, the total, a layer share bar,
  hands, a finger histogram, the 8 busiest keys of every layer (a click shows one), the layers reached, Export CSV… and
  Export JSON… (File ▸ Export's save panel), Clear Heatmap Data…, and "Counted on this Mac only. Nothing is uploaded."
- **"Layers reached", not "layer holds".** The keyboard reports which layer it is on, not why (ADR 0050), so a count of
  holds would also count locks and Sextant's own moves; the inspector names it for what it is.
- **Fingers** come from the board's data: `scripts/gen-board-definition.py` gives each key a hand and a finger from its
  half, cluster and column (the two outer columns of each half are the pinky's, then ring and middle, the two inner ones
  the index finger's; the thumb cluster the thumb's), touch typing's convention.
- **Exports** escape formula injection: every text cell is quoted, and one starting with `=`, `+`, `-`, `@`, a tab or a
  carriage return gets a leading apostrophe (the user's `=` key, a layer named "+1").
- **Menu bar.** While recording is on, one line under the mini map: "Today: 12,408 presses · 64 wpm", or why it is paused.
- **Amends ADR 0023:** key events still stay in memory, except that, once the user turns the heatmap on, hourly counts of
  key-downs per position are written as above.

## Consequences
- Nothing new is sent to the keyboard: recording only reads what a Live View session already reports. Agents test it on
  `FakeKeyboardLink`, `FakeDeviceWatcher`, an in-memory store and a test clock (`HeatmapRecorderTests`), and the files
  in a temporary folder (`HeatmapFilesTests`).
- Positions are counted, not keycodes: after an edit, a key's earlier presses stay on its position. A layer deleted
  since keeps its counts on disk but isn't shown or exported; Undo brings it back with them.
- Presses aren't counted while Sextant isn't running, while Live View is off, during the pairing handshake before the
  first layer report, or for firmware the library doesn't hold.
- A layout imported twice is recorded under the entry `OnKeyboard` picks (ADR 0039).
- The feed has no pairing event, so after Live View is turned off and on again, a keyboard found on another layer than
  the last one reported counts one move onto it.
- Files are per UTC day; "today" in the menu bar is the Mac's calendar day of the hourly buckets, so a half-hour time
  zone counts the hour that straddles midnight on one side.
- Words per minute counts every key-down (Backspace and modifiers too) as a fifth of a word: a rough rate, not a typing
  test.
