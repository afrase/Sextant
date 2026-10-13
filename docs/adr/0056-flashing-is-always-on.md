# 56. Flashing is always on in the app

Status: accepted, 2026-10-13. Amends ADRs 0012 and 0034 (the flashing half; the live-access gate stays).

## Context
ADRs 0012 and 0034 wired a refusing flasher unless a hidden user default (`SextantFlashingEnabled`) was set with
`defaults write`. The point was that no agent building or testing Sextant could write to the user's keyboard (AGENTS.md:
nothing is sent without the user's OK in chat). But the gate sat in the shipped app, so a user who clicked Build & Flash
got "Flashing is off" and a Terminal command to run. Oryx's own flow needs nothing like that. The user called it out:
the person who clicked Flash has already said yes.

## Decision
- The composition root always wires `DFUFlasher`. The user's Build & Flash, plus the app's own confirmation before
  replacing a keyboard that runs another layout, is the consent.
- The flasher's guards are unchanged and are what keeps a flash safe: writes only in `[0x08002000, 0x08042000)`, no
  mass erase, the DFU suffix's vendor, product and CRC checked against the connected bootloader, md5 verified, status
  polling capped, `dfuERROR` a failure.
- `SextantFlashingEnabled` is gone. Live access keeps its gate (ADR 0034): the raw-HID link pairs on its own as soon as a
  keyboard connects, without a click, so it stays behind `SextantLiveAccessEnabled` until the user decides otherwise.
- Agents still never flash: tests and the snapshot tool use fakes, and AGENTS.md's rule binds agents, not the app's users.

## Consequences
- Build & Flash works out of the box on any Mac. The "Flashing is off" path stays in the code for a disabled `Flasher`
  (tests), but the app no longer reaches it.
- README's hardware section now covers live access only.
