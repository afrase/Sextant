# Navigator trackpad prototype

Throwaway spikes from 2026-11-14 (research 06, ADR 0068). Reference only: nothing here is built by the package or `scripts/check`.

- `probe.swift`: lists the Voyager's HID interfaces and report descriptors, and logs input reports. Read-only, unless you pass `--set-ptp`, which writes feature report 4 = 3 to the trackpad interface.
- `navproto.swift`: the gesture engine the user tuned on the hardware. It switches the pad to touchpad mode, drives the pointer, clicks, drags and scrolls with `CGEvent`, and switches the pad back to mouse mode on exit. Its defaults are the tuned values ADR 0068 adopts.

Both write to the keyboard when run live. Under AGENTS.md, an agent needs the user's OK in chat before every live run. `--curve` and `--replay` touch no device.

The live run needs Input Monitoring and Accessibility for the app that launches it (Terminal, or the Claude app).
