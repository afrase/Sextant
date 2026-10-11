# 34. Separate switches for flashing and live access

Status: accepted, 2026-10-11. Refines ADR 0012.

## Context
ADR 0012 put raw-HID writes and flashing behind one user default, `SextantHardwareEnabled`, which only the user sets. On 2026-10-11 the user approved flashing their Voyager but not live access, whose pairing request also writes to the keyboard. One switch can't express that.

## Decision
- `SextantFlashingEnabled` wires the real `DFUFlasher`; `SextantLiveAccessEnabled` wires the real `RawHIDLink`. `SextantHardwareEnabled` still turns on both. All default to off and are set only by the user (or by the agent with the user's explicit approval in chat, for that switch).
- The `Flasher` port says whether it is enabled. With flashing off, Build & Flash builds and stops before asking for flash mode, so the keyboard is never left waiting in its bootloader for a write that would be refused.

## Consequences
- Flashing can be on while the live layer, Follow and key presses stay off (the toolbar and device card say live access is off).
- Every flasher guard (ADR 0013) applies unchanged.
