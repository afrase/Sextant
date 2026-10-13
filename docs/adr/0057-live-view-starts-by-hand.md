# 57. The live view starts only when the user turns it on

Status: accepted, 2026-10-13. Supersedes the live-access half of ADRs 0012 and 0034; amends spec §8.2.

## Context
The live link pairs with the keyboard (raw-HID writes `FE`, `00`, `01`) and then streams its layer and presses. Until
now it was gated by a hidden user default, `SextantLiveAccessEnabled`, and once that was set it paired automatically
whenever a keyboard was plugged in. ADR 0056 removed the flashing default because a user's click is the consent. The user
wants the same for live: no Terminal command, and nothing that starts on its own: "The live thing should be something you
have to manually launch. It shouldn't start automatically."

## Decision
- The real `RawHIDLink` is always wired; `SextantLiveAccessEnabled` and `SextantHardwareEnabled` are gone.
- `LiveSession` writes nothing until `startLive()`: a plugged-in keyboard shows as `.liveOff` (presence and the USB serial
  still work, so On keyboard, the firmware match and Build & Flash are unaffected). Live View is turned on and off from the
  toolbar's live button, Keyboard ▸ Live View, or the Device popover.
- Once on, it lasts across replugs until the user turns it off or quits. It never starts at launch and isn't remembered.
- Follow turns on when Live View starts (Settings › Keyboard › Follow the keyboard by default), not at connect.

## Consequences
- The menu bar extra, overlay HUD, Select Key by Pressing, heatmap recording and App Layers (v1 waves 3–4) all need Live
  View on; they say so instead of showing nothing.
- `LiveSession.Connection.hardwareAccessOff` became `.liveOff`, and a command sent while it's off throws `.notLive`.
