# 45. Keyboard and Advanced panes; the raw-HID trace stays in memory

Status: accepted, 2026-10-12. Amends ADR 0023.

## Context
Spec §8.9 adds two v1 Settings panes. Keyboard holds live presses, Follow and the overlay HUD's options; the global layer shortcuts come later, with slice 2.4. Advanced holds a developer raw-HID log and Reset all warnings. Spec §2.1 named the v1 panes "Keyboard, Shortcuts", which disagreed with §8.9.

Until now nothing read either live setting: `LiveSession.connect()` always turned Follow on, and each window always fed its board every press. The MVP deferred the Device popover's event monitor (ADR 0031). ADR 0023 says key events are kept in memory and never logged. A raw-HID log written to disk or os_log would break that, because os_log persists.

## Decision
- **Panes:** General, Keyboard, Build, Privacy, Advanced. Spec §2.1 now names §8.9's panes.
- **Show key presses on the board** (on by default; also a Device popover toggle). `followKeyboard(settings:)` feeds the board an empty set while it is off. A change applies at once, not at the next press: the setting is observed through `UserDefaults.didChangeNotification`. Only the board hides presses. The popover's Keys down row, `pressedKeys` and `activity()` don't change.
- **Follow the keyboard by default** (on). `LiveSession` takes a `followsOnConnect: @MainActor () -> Bool`, asked at every connect, so a change applies from the next connect. The composition root passes `KeyboardSettings.followsOnConnect`. The application layer never reads UserDefaults.
- **Overlay settings** are stored now and read by the HUD (slice 3.2): `showsOverlay` (on), `overlayDelayMilliseconds` (0–500 in 10 ms steps, 150), `overlayPosition` (`OverlayPosition`: bottom, top; bottom), `overlaySize` (`OverlaySize`: small, medium, large; medium), `tintsOverlay` (off, per taste call 9) and `lockedLayerOverlay` (`LockedLayerOverlay`: full, reminder, nothing; reminder). The enums and keys live in `KeyboardSettings.swift`. The HUD uses the same defaults.
- **Developer raw-HID log** (`RawHIDTrace`, application layer, `@MainActor @Observable`):
  - It is a ring buffer of the last 500 reports. Each entry holds the time, direction and bytes, plus the parsed event for a received report.
  - It is off at every launch. The switch isn't saved, so a log never runs unless the user turns it on in that session.
  - While it is off, its sink has no stream to feed and drops every report at the source, so nothing crosses to the main actor. Turning it off clears the buffer.
  - It is never written to disk or os_log. Copy Log is the only way out, and only when the user clicks it.
  - `RawHIDLink(trace:)` calls the sink after each write succeeds and for each report the session reads, including stale reports drained at open. A received report is cut after its stop byte, so the firmware's stack garbage is never kept. `08` and `FF` keep exactly two bytes, and a report with no stop byte keeps only its id. A sent report drops its zero padding by command length, because a trailing 0 can be a value (`04 01 00`, `05 00`). The write path doesn't change.
  - The composition root gives the sink only to the real link, which exists only with live access on. With live access off, `RefusingKeyboardLink` has no sink and the log stays empty.
  - `LiveSession` carries the trace (`live.trace`), so the Device popover and Settings reach it without a new service.
- **The Device popover** shows the log as a "Raw-HID log" disclosure while the log is on: time, → or ←, hex, and for key reports "down k40 · R8 C2". This also covers the deferred event monitor. A short log takes its own height; a longer one scrolls from the newest report, up to 150 pt tall.
- **Reset all warnings** removes every key in `SettingsKey.oneTimeNotes`, which holds only `seenLiveDataNote` today. The button is disabled while no note has been dismissed. A new one-time note adds its key to that list.
- **Heatmap retention** defaults to the spec's 30 days (it was 90).

## Consequences
- The log shows only what the link exchanges: handshakes, events and the ADR 0038 commands. The protocol carries matrix positions, never characters, so "positions only" holds without filtering.
- The trace adds no write: it observes reports the link already sends and receives.
- The log's 500-entry array drops its oldest entries in O(n) per append, which is negligible at keyboard rates.
- The HUD declares the same `@AppStorage` keys with the same defaults; a default changed in one place must change in the other.
- A pane that nothing reads yet (the overlay group, until slice 3.2) is stored for later, as General's "When the keyboard connects" already is.
