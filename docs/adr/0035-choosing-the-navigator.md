# 35. Choosing the Navigator, and trackball firmware for the pinned modules

Status: accepted, 2026-10-11

## Context
The user asked for what Oryx offers: configure a trackpad or a trackball and change sides. Sextant read and wrote `navigator` (kind, side, options) but had no way to add, remove or change it, and the board's disc stayed on the side the layout was opened with. Switching a real build to a trackball also showed that Sextant's trackball output, a copy of Oryx's e5Rrr sources, doesn't build with the pinned firmware (ADR 0033): its `POINTING_DEVICE_DRIVER = navigator_trackball` is refused ("not a valid pointing device type"). In that firmware the `zsa/navigator_trackball` module sets its own driver and handles the Navigator keycodes, which `zsa/defaults` declares for every build.

## Decision
- **Where:** Firmware Settings › Navigator is always shown. It starts with "Navigator" (None · Trackpad · Trackball) and "Side" (Left · Right, off with None), then the kind's settings, with a footnote that the choice must match the module attached and takes effect after a build and flash. The palette finds it as a setting row ("Navigator · Trackpad · Right").
- **Edits:** `EditSession.setNavigator(_:)` ("Set Navigator") and `moveNavigator(to:)` ("Move Navigator to Left/Right"), one undo step each, over the domain's `KeyboardLayout.setNavigator(_:)`. A new kind starts from its default options, because trackpad and trackball options differ, but keeps `automouseLayer`: Oryx stores that flag on the layer whatever the module, and Sextant has no other control for it. A new Navigator goes on the right. Moving keeps every option. The firmware has nothing per side.
- **Knob:** not offered (the generator refuses it). An imported knob shows as a fourth segment so the control reads true.
- **Board:** `EditSession.geometry` follows the layout's Navigator after every change, undo and redo included.
- **Trackball firmware:** `keymap.json` lists `zsa/navigator_trackball`; `rules.mk` keeps `POINTING_DEVICE_ENABLE = yes` without a driver; `keymap.c` no longer declares or handles `DRAG_SCROLL` and the `NAVIGATOR_*` keycodes (declaring them would declare them twice; handling them would step the CPI twice, since modules run before `process_record_user`). `config.h` is unchanged. The e5Rrr golden test names these as allowances.

## Consequences
- A trackball layout builds with the pinned firmware: the user's layout switched to a trackball, and e5Rrr with its automouse layer and Navigator keys, compile under the real toolchain (`SEXTANT_REAL_TOOLCHAIN=1`). Neither has run on a trackball; nobody here has one.
- The trackpad build is unchanged (same files, same 62,350 bytes).
- With no Navigator, Navigator keys should still compile (`zsa/defaults` declares them; not built yet) and do nothing.
- Trackball options the generator can't write yet (scroll only, rotation, aim and turbo speeds and layers) still make the build refuse when changed (ADR 0030); the trackball module supports them, so the generator can learn them.
