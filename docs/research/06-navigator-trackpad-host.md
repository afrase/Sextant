# 06 - Navigator trackpad on macOS: what the host sees

Study date: 2026-11-14. A read-only spike: what the Navigator trackpad sends to a Mac, and whether Sextant could drive gestures itself.
Device: the user's Voyager (PID `0x1977`) with a Navigator trackpad, Oryx-built firmware, ZSA's companion app not running.
Source: `zsa/qmk_modules@d7616bde` `navigator_trackpad/` (GPL-2.0).

## Method

A throwaway Swift probe (IOHIDManager) matched vendor `0x3297` and:
- listed each HID interface, its usages and its report descriptor (read from the IORegistry; no request reached the keyboard);
- opened only the digitizer interface, non-exclusively, and logged input reports for 30 s while the user moved one finger, tapped, scrolled with two fingers and tapped with two fingers.

Nothing was sent to the keyboard: no output, feature or GET_REPORT requests. Opening the interface needed **Input Monitoring** (it failed with `0xE00002E2`, not permitted, until the user allowed it).

## Findings

1. **macOS exposes the trackpad as its own HID interface**, primary usage `0x0D/0x05` (Digitizer › Touch Pad). The other interfaces are the keyboard (`0x01/0x06`), system/consumer/NKRO (`0x01/0x80`) and Oryx raw HID (`0xFF60/0x61`).
2. **The descriptor is a standard Windows Precision Touchpad (PTP)** (`rules.mk`: `DIGITIZER_MODE = touchpad`):
   - **Report 1 (input):** two fingers, each with confidence, tip, a 3-bit contact ID and X/Y. The coordinates run 0–2048 logical over 0–550 physical (0.01″ units, so 5.5″). Then scan time (16-bit, 100 µs units), contact count (4-bit), and buttons 1–3.
   - **Report 2 (feature):** device capabilities: max contact count, pad type, button type.
   - **Report 3 (feature):** a 256-byte vendor blob, the PTP certification status.
   - **Report 4 (feature):** input mode (`0x0D/0x52`). `0` means mouse and `3` means PTP (`navigator_trackpad_ptp.c` lines 60–66).
   - **Report 5 (feature):** selective reporting (surface and button switches).
   - **Report 6 (input):** a fallback mouse with three buttons and relative X/Y (−127…127). **It has no wheel.**
3. **On macOS the pad stays in mouse mode.** All 1,960 captured reports were report 6 and none were report 1. macOS never sets the input mode to PTP, so the firmware runs its fallback path (`navigator_trackpad_ptp.c` line 581):
   - Pointer movement is shaped on the keyboard (`TRACKPAD_MOUSE_SENSITIVITY 0.3`, `ACCELERATION 1.1`, `config.h`).
   - **Taps** arrive as left clicks: 11 in the capture.
   - **Two-finger taps** never produced a right click (button 2 never appeared).
   - **Two-finger scrolling** produced only pointer motion. There is no scroll field to carry it.
   - The rate is about 135 Hz (median gap 7.4 ms).
4. **This is why the Navigator "doesn't feel like a Mac trackpad."** The Mac only ever sees a small relative mouse, with the keyboard's acceleration curve and no scrolling. Everything trackpad-like has to come from a host app that switches the pad to PTP mode and interprets the contacts. That is what ZSA's closed companion app does, by its own description (04 §2.9). The firmware remembers the mode only in RAM (`prev_input_mode`), so it falls back to mouse mode whenever the keyboard power-cycles.

## Consequences for a Sextant gesture engine

- **Feasible with public APIs:**
  - Write feature report 4 = `3` to get two-finger contacts at about 135 Hz.
  - Post the pointer moves, clicks and phased scroll events (with momentum) with `CGEvent`.
  - Posting needs Accessibility; reading needs Input Monitoring.
- **Gestures beyond two fingers:**
  - Pinch, rotate and smart zoom need undocumented `CGEvent` gesture fields.
  - Three- and four-finger gestures need more contacts than the firmware's default of 2 (`post_config.h`), and possibly more than the Cirque Gen6 can track. Unverified.
- **The mode has to be re-asserted:** after every reconnect and wake, and on the keyboard's return from the bootloader.
## Spike 2: switching to PTP mode (the user approved this write, 2026-11-14)

The probe sent one `SET_REPORT` (feature, report 4, bytes `04 03`) to the digitizer interface and listened for 30 s. The user tapped, moved and scrolled with one, two and three fingers.

- **The switch works from macOS.** `IOHIDDeviceSetReport` returned success with no GET of reports 2 or 3 first. All 3,257 reports were report 1, and the mouse fallback went silent.
- **Nothing moves the cursor in PTP mode.** macOS ignores the digitizer reports and the fallback has stopped, so a host app must drive the pointer the whole time. Replugging restores mouse mode.
- **What the data looks like:**
  - **Report rate:** the scan time steps 6.5 ms (154 Hz), and the pad sends nothing while untouched.
  - **Ending a touch:** each contact ends with one frame where tip is 0.
  - **Confidence:** never 0 while tip was 1.
  - **Contact IDs are stable.** The first finger is ID 0 in slot 0, and the second is ID 1 in slot 1. When finger 0 lifts, finger 1 keeps its ID and slot.
  - **Coverage:** X and Y covered 44–2034 of 0–2048, about 51 units/mm on the roughly 40 mm pad.
- **Taps are easy to detect.**
  - One-finger taps lasted 33–65 ms with at most 60 units of travel (about 1 mm), and most moved under 10.
  - Two-finger taps lasted 120–130 ms, with the fingers 950–1,140 units (about 20 mm) apart.
  - Buttons were always 0. The pad has no physical click, so every click is the host's to synthesize.
- **Two-finger moves report both contacts throughout**, at separations of about 140–1,300 units.
  - **Possible artifacts:** a few two-contact touches had the contacts only 19–41 units (under 1 mm) apart. That may be the sensor or ZSA's smoothing splitting one finger. A gesture engine must not read those as two fingers.
- **Three fingers are reported as two at most.** Telling three fingers from two needs firmware work, if the sensor can do it at all.

## Next

The data is clean enough for a host gesture engine. The pieces:
1. Re-assert PTP mode on every connect and wake.
2. Track contacts by ID.
3. Drive the pointer with a macOS-like acceleration curve.
4. Turn tap timing and travel into clicks: one finger for a left click, two for a right click.
5. Post two-finger scrolling as phased `CGEvent` scrolls with momentum.

It needs an ADR before code: the app that runs it, the permissions, and replacing ZSA's companion app.

## Spike 3: a gesture prototype, tuned live (2026-11-14)

`design/navigator-prototype/navproto.swift` ran five 2-minute sessions on the user's Voyager, each with the user's OK. It switched the pad to PTP on start and back to mouse on exit every time, with no stuck states. It posts `CGEvent`s and needs Accessibility (`CGRequestPostEventAccess`) as well as Input Monitoring. What each round taught:

1. **First run:** a fixed smoothstep curve (5 to 42 pt/mm), a 120 ms settle, then flushing the motion it held.
   - **Precision was hard, and the pointer jerked.** The settle released its held motion in one jump. The gain followed single 6.5 ms frames, so one noisy frame multiplied the pointer's speed.
   - **Short two-finger touches launched momentum.** Fingers landing unevenly read as scrolls ending at 2,500–10,000 px/s.
2. **Fixes:**
   - Motion during the settle is dropped, not replayed.
   - The gain uses speed smoothed over 25–40 ms, and a frame faster than 3× that is clamped.
   - The last two frames before a lift are dropped (fingertip roll), at about 13 ms of latency.
   - A touch is two-finger only after both contacts last about 40 ms, since 2-frame blips of a second contact are common.
   - Momentum is capped at 6,000 px/s.
3. **Dragging:** the user's main complaint, and the reason they turned dragging off in ZSA's app.
   - **Drag lock** (the button held 0.6 s after a lift) kept drags going when the user meant to drop. Off by default now.
   - **Tap-and-a-half** ("tap, then touch and move within 250 ms") turned repositions into drags.
   - **The fix:** the second touch must land within 4 mm of the tap on the pad, within 200 ms, and only after a clean tap (≤ 0.5 mm of travel). A reposition lands elsewhere on a 40 mm pad. The user: "a bit better".
   - The Navigator has no pressure, size or physical click (`cgen6_finger_t` is tip, confidence, ID, X, Y), so a click key on the keyboard is the only drag as reliable as a Mac trackpad's. The prototype reports drags while button 1 is held. **Tested 2026-11-14 (the user flashed Left Click on Sym+Num, key 19):** the key's button reaches the Mac while the pad is in PTP mode, and holding it while moving drags (text selection followed the finger).
4. **Apple's own curve:** the user still found the low end wrong.
   - The built-in trackpad's IOHIDEventService publishes `HIDAccelCurves`, ten parametric curves indexed by tracking speed. Evaluating them as IOHIDFamily's `IOHIPointing.cpp` does (`PACurvesSetupAccelParams`, `PACurvesGetAccelerationMultiplier`) gives 4.3, 11.6, 23 and 49 pt/mm at 5, 50, 100 and 180 mm/s for the user's 0.6875.
   - The hand-made curve gave 3, 4.5, 13 and 30: too slow in the middle, then lurching.
   - With Apple's curve, the user found long moves overshot. Keeping 60% of the curve's extra gain above 100 mm/s (38 and 55 pt/mm at 180 and 300) felt "good enough" and became the default.

ZSA's companion app (screenshots, 2026-11-14) has the same settings areas: Cursor, Scrolling, Tapping, Dragging, plus General and Logging. Its defaults explain the user's experience:
- A tap may last 0.45 s, while the user's real taps took 33–80 ms.
- Dragging is tap-then-touch with a 0.25 s re-grip window and no location check.
