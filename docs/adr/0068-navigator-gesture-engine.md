# 68. Sextant drives the Navigator trackpad: a gesture engine on the Mac

Status: accepted, 2026-11-14. The user accepted the recommendation on all three open calls (process, ZSA's app, licensing).

## Context
On macOS the Navigator trackpad acts as a small mouse (research 06).
- **What the firmware offers:** ZSA's firmware (`zsa/qmk_modules` `navigator_trackpad`) presents a Windows Precision Touchpad: two contacts at 154 Hz, plus a fallback mouse.
- **What macOS does with it:** it never sets the PTP input mode, so the pad stays on the fallback. The Mac gets relative motion shaped by the keyboard's own acceleration, with tap-to-click, no scrolling and no right click.
- **What ZSA's answer is:** a closed companion app. The user finds it doesn't feel like a Mac trackpad, and turned its dragging off because it never worked well.

Three spikes on the user's Voyager, each write approved in chat, showed what Sextant can do itself:
- Writing feature report 4 = 3 switches the pad to PTP from macOS.
- The contact data is clean: stable IDs, a lift frame, no pressure.
- A host engine posting `CGEvent`s feels right after tuning. The user called it "good enough for now".

The tuned prototype is `design/navigator-prototype/navproto.swift`.

## Decision
- **Sextant gets an opt-in Navigator trackpad driver.** Settings › Navigator › "Use Sextant for the Navigator trackpad" is off by default. Turning it on is the user's consent to Sextant setting the pad's input mode, the way Live View's toggle is for pairing (ADR 0057). While it's on, Sextant:
  - writes report 4 = 3 when the trackpad interface appears and after the Mac wakes;
  - writes report 4 = 0 when the toggle goes off and when Sextant quits.

  It writes nothing else. A Navigator trackball, or no Navigator, shows the section disabled.
- **The engine is the prototype's, made production code:**
  - **Pointer:** Apple's trackpad acceleration curve, read at run time from the Mac's own trackpad service (`HIDAccelCurves`) and interpolated at the user's tracking speed (`com.apple.trackpad.scaling`). Above a knee of 100 mm/s, only 60% of the curve's extra gain is kept. Speed is smoothed over about 25 ms, single-frame spikes are clamped, motion in the first 120 ms or 0.5 mm of a touch is dropped, and the last two frames before a lift are dropped. With no Apple trackpad to read, it falls back to a built-in copy of the standard curve set.
  - **Scrolling:** two contacts that both last about 40 ms scroll with phased continuous `CGEvent`s. The axis locks once the first 6 mm show a direction, and momentum follows the lift (capped at 6,000 px/s). Direction follows the system's natural-scrolling setting.
  - **Taps:**
    - One finger: under 180 ms and 1.2 mm of travel is a left click. Click counts follow the system double-click interval.
    - Two fingers: under 220 ms is a right click.
  - **Dragging:** after a clean tap, a touch that lands within 4 mm of it on the pad, within 200 ms, drags until the finger lifts. Re-grip (drag lock) is off by default. While mouse button 1 is held by a keyboard key, pointer motion posts as a drag.
- **Every tuning value is a setting with a unit, and macOS's own settings stay macOS's.** The sections are Pointer, Scrolling, Tapping and Dragging, shown in the table below. Tracking speed, double-click speed and scroll direction default to "follow System Settings" and can be overridden. Raw sensor units never appear in the UI, and each section has Reset to Defaults.
- **The layers (ADR 5):**
  - **Domain:**
    - `TrackpadFrame` and `Contact`;
    - `TrackpadSettings` (Codable, with defaults);
    - `PointerCurve`, the parametric evaluator;
    - `GestureEngine`, a value-type state machine. It takes timestamped frames and clock ticks and returns `PointerIntent`s: move (dx, dy, dragging), button (which, down or up, count) and scroll (dx, dy, phase, momentum phase).
  - **Application:**
    - `TrackpadDriver`, an actor, which owns the engine, applies settings, runs momentum on the injected clock and re-asserts the mode;
    - three new ports: `TrackpadLink` (frames as an `AsyncStream`, `setInputMode`), `PointerOutput` (posts intents, reports Accessibility) and `PointerCurveSource`.
  - **Adapters:**
    - `SextantDevice` gains `IOHIDTrackpadLink`, for the digitizer interface. It parses report 1 and writes only report 4.
    - A new `SextantPointer` target holds `CGEventPointerOutput` and `IORegistryCurveSource`.
  - **UI:** the Settings tab, with live permission rows: Input Monitoring and Accessibility, each with a button that opens System Settings.
- **The engine runs inside Sextant.** It keeps working while Sextant sits in the menu bar with no windows (ADR 0049), and a new "Open at login" setting covers restarts. The user's call: in Sextant first, and a helper only if crashes show up (Settled 1).

### Defaults

| Section | Setting | Default |
|---|---|---|
| Pointer | Tracking speed | follows System Settings (0.6875 on the user's Mac) |
| | Fast moves | 60% of Apple's extra acceleration above 100 mm/s |
| | Pad scale (advanced) | 1.0 |
| | Lift filter (advanced) | on, 2 frames |
| Scrolling | Speed | 1.0 (9–28 px per mm) |
| | Direction | follows System Settings; invert each axis optionally |
| | Momentum | on; glide keeps 99.7% of velocity per ms |
| Tapping | Tap to click | on |
| | Two-finger tap = right click | on |
| | Longest tap | 180 ms (two fingers: 220 ms) |
| | Most movement in a tap | 1.2 mm (two fingers: 2.4 mm) |
| | Double-click speed | follows System Settings |
| Dragging | Tap then touch to drag | on |
| | Second touch within | 200 ms and 4 mm of the tap |
| | Re-grip after lifting | off (0.6 s when on) |

## Settled (the user's calls, 2026-11-14)
1. **In Sextant or a helper.** If Sextant crashes, the pad stays in PTP mode and the Navigator's pointer is dead until the keyboard is replugged. A small login-item agent (`SMAppService.agent` with KeepAlive) would restart and restore it. The costs are a second process, its own Input Monitoring and Accessibility grants, and settings shared across processes. Decided: start in Sextant, since replugging is the recovery, and move to an agent if crashes show up.
2. **Coexisting with ZSA's companion app.** Both apps would write the input mode and post events. Decided: Sextant replaces it for users who turn the driver on. Settings says so, and asks them to quit ZSA's app. This reverses research 04 §2.9's "coexist, don't replace", for this feature only. Detecting ZSA's app needs its bundle identifier, which isn't known yet.

## Consequences
- **Hardware safety:** Sextant gains its first automatic device write outside Live View and Build & Flash. AGENTS.md's rule still binds agents: tests use a fake `TrackpadLink`, and a real-pad test runs only with the user's OK, like `RealKeyboardTests`.
- **Licensing:** the curve evaluator re-expresses about 60 lines of `IOHIPointing.cpp`, which is APSL-2.0. That file carries an APSL-2.0 header and attribution, so the repo becomes MIT plus one APSL file (`design/navigator-prototype/navproto.swift` is marked the same way). The curve data is read from the user's own Mac at run time, with a fallback copy of the ten standard curves. The alternative is a curve written from scratch, which loses the "feels like my MacBook" match. The user accepted the APSL file (2026-11-14).
- **Not possible:**
  - three- and four-finger gestures: the firmware reports two contacts;
  - pressure, force click and a physical click: the pad has neither, and the click key is the substitute;
  - pinch and rotate: they would need undocumented `CGEvent` gesture fields.
- **Untested:**
  - whether QMK mouse keys still reach the Mac while the pad is in PTP mode (the click key depends on it);
  - the wake path, and a reconnect from the bootloader;
  - Navigators on both halves;
  - a Magic Trackpad as the curve source.
