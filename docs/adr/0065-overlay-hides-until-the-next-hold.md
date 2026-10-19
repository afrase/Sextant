# 65. Typing can hide the overlay until the next hold

Status: accepted, 2026-10-19. Amends ADR 0064 and spec §8.4.

## Context
ADR 0064's option hides the full overlay while you type on a layer and brings it back once you pause for the delay. The
user asked for another choice: once a key is pressed over the overlay, keep it hidden until the layer key is pressed again.
Neither had been released (v0.4.0 was still unpublished), so the stored setting could change shape.

## Decision
- **One setting, three choices:** Settings › Keyboard › Overlay › When you type on the layer: Keep showing (the default),
  Hide until you pause (ADR 0064's behaviour), Hide until the next hold. Stored as `overlayTyping` (`keepShowing`,
  `hideUntilPause`, `hideUntilNextHold`), in place of ADR 0064's `overlayHidesWhileTyping` Bool, which no release read.
- **Hide until the next hold:** the same keys hide it as in ADR 0064 (any key but the holder or a layer key, over the full
  overlay, held or locked), and it stays hidden however long the keys are up. It ends, as in ADR 0064, when what should show
  changes: letting go of the layer key (so the next hold shows after the delay), another layer, Live View off, secure input,
  a key window on the layer, or the setting changing. A locked layer's full overlay stays hidden until the keyboard moves to
  another layer. The reminder pill still doesn't hide.

## Consequences
- The two hiding behaviours can't both be on, which matches how they read; a picker says so where two toggles wouldn't.
- Holding another layer from the hidden one shows that layer after the delay, as any layer with nothing showing does.
