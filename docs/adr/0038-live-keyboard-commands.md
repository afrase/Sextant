# 38. Live keyboard commands: what may be sent, and when

Status: accepted, 2026-10-12. Amends ADRs 0012, 0022, 0023 and 0034.

## Context
Several v1 features write to the keyboard over the live connection. The menu bar tiles, the layer shortcuts, the Keyboard menu and App Layers move its layer (`04 01 n`). The lighting preview takes over its lights (`05`, `06`, `09`). Until now the link only queried and paired (`FE`, `00`, `01`) and then read events.

The Oryx module (`zsa/qmk_modules@13890cd`, research 03 §3.3) accepts more commands than these. Two of them don't bounds-check: `04` shifts 1 by the raw layer number, which is undefined from 32 on, and `06` indexes the 52-entry LED array with the raw byte. The paired flag and `rgb_control` are firmware globals, shared with every host that has the interface open (Keymapp, Oryx in Chrome).

LiveSession's 60 Hz debounce (ADR 0023) also drops a tap shorter than one frame, and the heatmap and Select Key need every key-down and key-up.

## Decision
- **One channel.** `KeyboardLink.session(with:board:commands:)` takes an `AsyncStream<KeyboardCommand>`. RawHIDLink merges it into the session's input loop, so each command meets the session's phase in order. It writes only in the paired (`live`) phase; a command that arrives earlier is dropped, never queued. Paired writes go out from a writer task, in order and with the handshake's 5 ms pacing (ADR 0022), so the pacing never holds back the keyboard's reports. Each session gets a fresh stream, so a command never reaches a later session.
- **Four commands, nothing else.** Each is a zero-padded 32-byte report with report ID 0:
  - `.moveToLayer(n)`: `04 01 n` (layer_move: momentary layers drop, the default layer stays);
  - `.lighting(Bool)`: `05 01` takes the lights, `05 00` gives them back and reloads the board's own lighting;
  - `.setLED(index:red:green:blue:)`: `06 i r g b`;
  - `.setAllLEDs(red:green:blue:)`: `09 r g b`.

  A layer move is followed by `01`. The firmware drops a layer event that equals its `current_layer`, which pairing never updates (research 03 O2), so a move back to that layer goes unreported; pairing again always reports the layer.

  Nothing else can be encoded: not `03` (unhandled), `04 00` (layer_off), `07` or `0A` (status LEDs), `08` (brightness steps, which change the board's own state), `0B` or `0C` (automouse, not in the build).
- **Clamps.** `KeyboardCommand.isAllowed(on:)` refuses a layer outside 0–31 and an LED index outside the board's keys (0–51; the LED index is the key index, as `BoardDefinition` states). LiveSession checks it and throws `outOfRange`. The encoder checks it again and writes nothing. A layer below 32 is not always a real move: a build for fewer than 16 layers keeps an 8- or 16-bit layer state, and a layer past it truncates to no layer at all, dropping the board to its default layer. So callers clamp to the layers of the layout on the keyboard.
- **Who may send.** `LiveSession.send(_:)` throws:
  - `notFound` with no keyboard;
  - `hardwareAccessOff` when live access is off;
  - `heldByAnotherApp` while Keymapp holds the interface;
  - `notLive` in flash mode, and until the session has reported its layer;
  - `outOfRange` as above.

  `canSend` is true only while a paired session is open, never for the last state of one that already ended. RefusingKeyboardLink never reads its commands. A failed write ends the session with the IOKit error, so Keymapp seizing the interface after pairing now shows up. LiveSession then reconnects as before.
- **When.** Only on a user gesture (a click, a shortcut, a menu item, the preview toggle) or by a rule the user turned on (App Layers). Nothing is sent at launch or on connect unless such a rule says so.
- **Release paths** for the lighting preview (built in slice 3.3): `05 00` on toggle off, lens exit, layout switch, window close, sleep, and quit. Quit waits a bounded time, because `IOHIDDeviceSetReport` has no timeout; the `08 00` reply, which `activity()` delivers as `.lighting(false)`, can end the wait early. Nothing is sent on disconnect. After a crash the colors stay until the board is unplugged, and the next launch sends nothing to repair them.
- **Replies.** `08 <state>` parses to `LiveEvent.lighting` and `FF <code>` to `LiveEvent.error`. Neither has a stop byte, so exactly byte 1 is read. `activity()` hands them on as `.lighting` and `.refused`.
- **Activity feed.** `LiveSession.activity()` streams every key-down (key index, plus the layer at that moment), key-up and layer change, and the two replies. They are tapped while events are folded, before the debounce, so a tap under 16 ms survives. A layer is reported only when it differs from the last one reported for that keyboard, because every pairing repeats it. A key-down before the session's first layer report has no layer to carry and is left out; that happens only during the handshake, when another host paired the board earlier. The feed is silent during secure input, checked at every event rather than by the 1 Hz poll, so the first keys typed into a password field never reach it. It stays in memory; nothing is logged or stored. So a key-down can arrive without its key-up, or the reverse (left out before the first layer, or secure input changing between the two); a consumer that tracks held keys (the HUD, Select Key by Pressing) must tolerate an unpaired event.
- **Hardware approval.** Turning on live access (ADR 0034) does not approve the agent sending these. Trying SET_LAYER (`04 01 n`, then `01`) or the RGB takeover on the user's Voyager needs the user's OK in chat for that category.

## Consequences
- Nothing in the app sends yet. Later slices build on this channel and test against FakeKeyboardLink, which records each session's commands, and FakeHID.
- `send` doesn't wait for the write. A write that fails shows in `connection` (the session ends), not as an error from `send`.
- The command queue is unbounded and drains at one write per 5 ms (52 LED writes take about 260 ms), so a sender that can outpace it, like the lighting preview, coalesces before sending.
- Paired state is shared. A layer move from Sextant also moves the layer Oryx in Chrome or Keymapp shows, and either host's `05 00` ends the other's takeover. Pairing lasts until the board reboots (research 03 §3.5).
- If another host already paired the board, its events can reach Sextant during the handshake. `canSend` may then turn true before RawHIDLink's own pairing finishes (normally a few milliseconds later), and commands in that gap are dropped.
