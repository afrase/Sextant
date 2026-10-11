# Sextant

Sextant is a native macOS 26 SwiftUI app for configuring the user's ZSA Voyager. It edits layouts locally, imports from Oryx, builds QMK firmware, flashes it, and shows the keyboard live. It is not affiliated with ZSA.

## Start here

- `docs/design/ui-spec.md`: what to build. §13 covers targets, APIs and the MVP build order. §14 lists the taste calls, all decided.
- `docs/research/00-overview.md`: how Oryx, the firmware, the flasher and live HID work, plus the architecture and its risks. Section 4 covers flasher safety.
- `docs/decisions.md`: settled decisions, plus what is still open.

**Status:** research and UI design are done. Next come the code design and the MVP build.

## Code

- **Toolchain:** SwiftPM, Swift 6, macOS 26. No third-party dependencies unless the user agrees.
- **Module names:** never name a module exactly `Sextant`. Spec §13.1 proposes `SextantKit`, `SextantBoard`, `SextantDevice`, `SextantBuild` and `SextantApp`.
- **`design/` is reference, not production code:**
  - `design/PrototypeKit` (model, legends, keycodes, geometry, samples) is the seed for `SextantKit`. Port it; don't depend on it.
  - Don't edit `design/explorations/` or `design/judging/`.
- **Tests:** `docs/research/oryx-examples/` holds real Oryx JSON and its generated QMK source, for golden tests.
- **No TCC prompts in automated runs.** Don't use screencapture or ScreenCaptureKit. Render UI offscreen, the way PrototypeKit's `SnapshotRunner` does.

## Hardware safety (non-negotiable)

- Never send anything to the keyboard without the user's explicit OK in chat, given for that action. This covers raw HID writes, RGB takeover, entering the bootloader and DFU. Read-only enumeration is fine.
- **Flasher guards:**
  - only write within `[0x08002000, 0x08042000)`, and never MASS_ERASE;
  - the DFU suffix VID, PID and CRC must match the connected bootloader (`3297:0791` STM32 or `3297:1791` GD32);
  - md5-verify the image;
  - cap status polling, and treat `dfuERROR` as failure.
- Generated firmware must keep the Navigator trackpad (ZSA's modules) working.

## External services and repo

- **Oryx:** reads only, through its public GraphQL. No logins and no mutations.
- **Branding:** no ZSA trade dress (logos, Voyager art, Oryx colours). Use "ZSA Voyager" in text only.
- **Git:** commit when the user asks, and never push without asking. Before any public push, remove the ZSA-derived material: `docs/research/data/oryx-keycodes.json`, `docs/oryx-ui/`, and the other people's layouts in `docs/research/oryx-examples/`.
