# 22. Device I/O policy: raw HID and DFU

Status: accepted, 2026-10-11

## Context
`RawHIDLink` and `DFUFlasher` talk to the keyboard. Both are behind the hardware gate (ADR 0012) and tested only against fakes until the Phase 0 spike is approved, so their timing and acceptance rules must be explicit.

## Decision
- **Raw HID:** match VID, PID and usage page `0xFF60` / usage `0x61` only; find the interface by walking IORegistry parents to the watcher's device (never by serial); open with `kIOHIDOptionsTypeNone` (never seize; `IOHIDManagerOpen` is never called). Accept protocol `0x02` and up, never an equality check; send pairing only after a version reply. Give up (for LiveSession to retry with backoff) without a version reply in 2 × 400 ms or a layer event within 700 ms. Pace writes 5 ms apart; drop key positions outside the board's matrix.
- **DFU:** every DfuSe DNLOAD passes one guard function (address window, page-aligned erase, no MASS_ERASE, block bounds) after a pre-transfer check of the opened device's VID/PID against the PID the image was validated for. At most 1000 GETSTATUS polls and 5 s per wait, sleeps clamped to 1 ms–2 s, 5 s per transfer. Once started, a flash runs to the end even if its caller is cancelled, so cancellation can't leave the keyboard half-erased; a second concurrent flash is refused. Leave in zapp's form after a 1 s settle.
- Interfaces get up to 1 s to appear after hotplug.

## Consequences
- Guard refusals surface as `FlashError.transfer("Refused …")`: they can only trip on a bug.
- GD32 (`0x1791`) boards can't be flashed until dual images are understood (research 00 §7 risk 1).
- Unproven on hardware: the handshake timings, IOUSBHost access to Ignition's DFU interface.
