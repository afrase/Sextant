# 64. The overlay can hide while typing on the layer

Status: accepted, 2026-10-19. Amends ADRs 0050 (the HUD) and 0062 (its settings) and spec §8.4.

## Context
The user asked for an option to dismiss the overlay on a key press: holding a layer to type several keys on it, the overlay
can sit over what they're typing into. They suggested showing it again once no key has been pressed for a while, perhaps
for the overlay's delay.

## Decision
- **Setting:** Settings › Keyboard › Overlay › Hide while typing on the layer, off by default (an option, as asked; the
  overlay behaves as before unless it is turned on). Stored as `overlayHidesWhileTyping`.
- **What hides it:** a key-down while the full overlay should show, held or locked, other than the key holding the layer.
  It hides at once, like every other hide. A key pressed while the overlay still waits for its delay holds it back too, so
  a quick hold-and-type never shows it.
- **What doesn't:** a layer key (any key with a layer action: MO, LT's hold, TG, TO, TT, OSL, LM, DF): the layer it moves
  to shows by the usual rules, so a second held layer still replaces a held one at once. The locked layer's reminder pill
  is small and stays.
- **Showing again:** once every key that hid it is up and no other went down for the delay, the same overlay shows again
  with no second wait. The delay is the user's existing setting, with a floor of 100 ms so a delay of 0 doesn't flash it
  back between keystrokes.
- **Forgetting:** anything that changes what should show (the holder let go, another layer, Live View off, secure input, a
  key window showing the layer, the setting turned off) ends it; the next hold starts fresh.

## Consequences
- The overlay can now come and go while a layer is held, which is what the user asked for; with the option off nothing
  changes.
- A layer-tap key tapped on a held layer to type its tap doesn't hide the overlay, since it is also a layer key. Rare on a
  held layer, and treating it as typing would hide the overlay when it is used to move layers.
