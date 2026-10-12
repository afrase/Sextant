# 41. Tap dance checks and per-key tapping terms

Status: accepted, 2026-10-12. v1 plan slice 1.1. Builds the per-key tapping term that ADR 0027 left out.

## Context
The generator builds tap dances (the e5Rrr and JRGQm goldens), but a dance slot whose action its C can't run failed only at build time: a macro, a color key, a firmware key, TG, TT, OSL, LM, DF or OSM, or a tap that isn't a key. Spec §7.5 wants these caught as live issues first. `Key.tappingTerm` round-trips through Oryx's JSON and the generator writes it, but nothing in Sextant edits it, and the generator drops it without a word while the `perKeyTappingTerm` setting is off. Oryx's "Prefer tap in tap-and-hold dances" (`dancesTapAction`) sits on the Tapping section, but Oryx's output is the same with it on or off (research 02 §4.4; ADR 0040 lists it among the settings that write nothing).

## Decision
- **The domain decides what can run in a dance:** `KeyAction.runsInTapDance` (a key, modifiers, or MO or TO with a layer) and `typesInTapDance` (a `KC_` or locale code: the tap is also typed on three or more taps). `KeymapPlan.token` uses them. `QMKCodes.statements` still writes the C, and a test checks that the two agree for every catalog code and alias, plain, with a layer, a chord, a color or a macro, and for unknown codes. The domain finds locale codes by their catalog category and the generator by its `i18n.h` table; the test catches any drift.
- **Live issues:** `.notInTapDance` (an error) lands on each dance slot that can't run, and on the tap when it isn't a key. `.tappingTermIgnored` (a warning) lands on a key, with no slot, that has its own term while per-key terms are off. Oryx built every fixture, and none of the seven raises either.
- **Setting a term** (`KeyboardLayout.setTappingTerm`): the value is kept within 0…1000, a value equal to the global term is stored as nil (as Oryx does), and every key on any layer with the same four actions gets the same value. QMK looks terms up by keycode, so those keys share one term anyway; a label or LED color doesn't change the keycode. Dance and dual-function tokens are unique per key, so copying to an identical one is harmless. The global term is the stored `tappingTerm` or 200, read the way the generator reads `TAPPING_TERM`.
- **`EditSession.setTappingTerm`** is one undo step, "Set Tapping Term". A custom term also turns `perKeyTappingTerm` on in that step, since the firmware ignores the term otherwise. Going back to Global leaves the setting on: other keys may still use it.
- **The inspector row** (spec §5.1 item 7) shows when the key has a hold, a double tap or a tap then hold, read from the slots rather than `kind` (a label or macro changes the kind, not the timing). It also shows for any key that already has its own term, so an imported one can be set back to Global.
  - A pop-up offers "Global (200 ms)" or Custom; ADR 0027 keeps segmented controls out of the 280 pt inspector.
  - Custom adds a field and a 10 ms stepper, plus the difference: "+20 ms from global". Each stepper click is one step. A typed value commits on Return, when focus leaves or when the key changes. On macOS 26 the field reports every keystroke, so the row keeps the typed value as a draft. Only a typed draft commits when the row goes, so a row that goes because its key changed (a swap, an undo) can't write its old value onto the new key.
  - Choosing Custom stores nothing until the value changes. A value equal to the global term is stored as Global, and the row goes back to Global.
  - The label and term fields share one focus in the key inspector, so moving between them can't leave ⌘⌫ and ⇧⌘⌫ pointed at the key.
- **`dancesTapAction` is hidden** from the Firmware Settings page and the palette, since Oryx's firmware is the same either way. An imported value is kept, and the generator still writes nothing for it.

## Consequences
- Changing the global term leaves per-key terms as absolute values, as in Oryx, so a term that now equals the global one stays stored until it is set again.
- Copying by actions only approximates copying by token. Two keys that differ only in an action's description share a token but not the copy; the generator then uses the first key's term, as before.
- A dual-function key (a tap and a hold, no dance) whose action can't run is still refused only at build time. That is outside this slice's issue kinds.
- Dance timing and terms can only be felt after a flash, and each flash needs the user's OK.
- Design-QA scenes: new `inspector-dance-flagged` and `inspector-term-custom` scenes (light and dark); the `firmware-settings` scenes lose the dances row. The reference snapshots and the five goldens are unchanged.
