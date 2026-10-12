# 12. Hardware writes are wired off until the user approves them

Status: accepted, 2026-10-11

## Context
AGENTS.md forbids sending anything to the keyboard (raw-HID writes, RGB takeover, bootloader, DFU) without the user's explicit OK for that action. Even reading the live layer needs a write: Oryx protocol pairing (`01`). The agent runs the app during development, sometimes with the keyboard plugged in.

## Decision
The composition root wires `KeyboardLink` and `Flasher` to refusing implementations that throw a typed "hardware access is off" error. The real `RawHIDLink` and `DFUFlasher` are wired only when the `SextantHardwareEnabled` user default is true, which only the user sets. Read-only enumeration (`IOKitDeviceWatcher`: presence, serial, PID, bcdDevice) is always on. Both real adapters are built and unit-tested against fake transports.

## Consequences
- Nothing the agent runs can write to the keyboard.
- Live layer, presses and flashing stay unproven on hardware until the Phase 0 spike is approved (tracked in `docs/progress.md`).
- Before release, the gate becomes the normal Settings › Privacy explanation, with the default on.
