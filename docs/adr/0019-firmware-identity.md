# 19. Firmware identity: Oryx's serial when unchanged, otherwise a Sextant fingerprint

Status: accepted, 2026-10-11. Resolves research 00 §9 decision 4 for now.

## Context
The keyboard reports its firmware's `SERIAL_NUMBER` over USB. Oryx, Keymapp and zapp read `layout/revision` from it to fetch the layout from Oryx. Sextant builds need an identity that never makes those tools fetch a stale Oryx layout, and that lets Sextant tell "runs exactly this layout" from "runs an older build of it".

## Decision
- A layout with Oryx provenance that still equals its latest import revision builds with Oryx's own `layoutId/revisionId` serial.
- Anything else builds with `sx-<first 8 hex of the library UUID>-<DFU CRC-32 hex of the layout's canonical JSON>` (20 ASCII characters, no `/`), within QMK's USB serial and the 30-byte raw-HID reply.
- Matching: *current* when the serial equals the expected identity; *this layout* when it starts with `sx-<this library id>-` or `<Oryx layout id>/`; otherwise *another layout*, which triggers the "Replace the layout on this keyboard?" confirmation.
- The generator only accepts serials matching `[A-Za-z0-9/._-]{1,30}` (ADR 0020); a test builds the user's layout with a Sextant identity to keep both sides in step.

## Consequences
- Oryx-unchanged builds stay interoperable with Keymapp and zapp; edited builds are invisible to them as Oryx layouts.
- A rename alone changes the fingerprint, because the title is part of the content.
- Unverified on hardware: how Keymapp and zapp treat an `sx-` serial (research 00 §10 item 27).
