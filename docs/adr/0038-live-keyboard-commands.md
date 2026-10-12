# 38. Live keyboard commands: what may be sent, and when

Status: accepted, 2026-10-12. Amends ADRs 0012, 0022, 0023 and 0034.

## Context
Several v1 features write to the keyboard over the live connection. The menu bar tiles, the layer shortcuts, the Keyboard menu and App Layers move its layer (`04 01 n`). The lighting preview takes over its lights (`05`, `06`, `09`). Until now the link only queried and paired (`FE`, `00`, `01`) and then read events.

The Oryx module (`zsa/qmk_modules@13890cd`, research 03 §3.3) accepts more commands than these. Two of them don't bounds-check: `04` computes `1 << layer` in a 32-bit layer state, and `06` indexes the 52-entry LED array with the raw byte. The paired flag and `rgb_control` are firmware globals, shared with every host that has the interface open (Keymapp, Oryx in Chrome).

LiveSession's 60 Hz debounce (ADR 0023) also drops a tap shorter than one frame, and the heatmap and Select Key need every key-down.

## Decision
- **One channel.** `KeyboardLink.session(with:board:commands:)` takes an `AsyncStream<KeyboardCommand>`. RawHIDLink merges it into the session's single input loop, so commands are written in order with the handshake's 5 ms pacing (ADR 0022). It writes only in the paired (`live`) phase; a command that arrives earlier is dropped, never queued. Each session gets a fresh stream, so a command never reaches a later session.
- **Four commands, nothing else.** Each is a zero-padded 32-byte report with report ID 0:
  - `.moveToLayer(n)`: `04 01 n` (layer_move: momentary layers drop, the default layer stays);
  - `.lighting(Bool)`: `05 01` takes the lights, `05 00` gives them back and reloads the board's own lighting;
  - `.setLED(index:red:green:blue:)`: `06 i r g b`;
  - `.setAllLEDs(red:green:blue:)`: `09 r g b`.

  Nothing else can be encoded: not `03` (unhandled), `04 00` (layer_off), `07` or `0A` (status LEDs), `08` (brightness steps, which change the board's own state), `0B` or `0C` (automouse, not in the build).
- **Clamps.** `KeyboardCommand.isAllowed(on:)` refuses a layer outside 0–31 and an LED index outside the board's keys (0–51; the LED index is the key index, ADR 0017). LiveSession checks it and throws `outOfRange`. The encoder checks it again and writes nothing. Callers narrow further, for example to the layers of the layout on the keyboard.
- **Who may send.** `LiveSession.send(_:)` throws:
  - `notFound` with no keyboard, or one in flash mode;
  - `hardwareAccessOff` when live access is off;
  - `heldByAnotherApp` while Keymapp holds the interface;
  - `notLive` until the session has reported its layer;
  - `outOfRange` as above.

  `canSend` is true only while a paired session is open. RefusingKeyboardLink never reads its commands. A failed write ends the session with the IOKit error, so Keymapp seizing the interface after pairing now shows up. LiveSession then reconnects as before.
- **When.** Only on a user gesture (a click, a shortcut, a menu item, the preview toggle) or by a rule the user turned on (App Layers). Nothing is sent at launch or on connect unless such a rule says so.
- **Release paths** for the lighting preview (built in slice 3.3): `05 00` on toggle off, lens exit, layout switch, window close, sleep, and quit. Quit waits a bounded time, because `IOHIDDeviceSetReport` has no timeout. Nothing is sent on disconnect. After a crash the colors stay until the board is unplugged, and the next launch sends nothing to repair them.
- **Replies.** `08 <state>` parses to `LiveEvent.lighting` and `FF <code>` to `LiveEvent.error`. Neither has a stop byte, so exactly byte 1 is read.
- **Activity feed.** `LiveSession.activity()` streams every key-down (key index, plus the layer at that moment) and every layer change. They are tapped while events are folded, before the debounce, so a tap under 16 ms survives. The feed is silent during secure input and stays in memory; nothing is logged or stored.
- **Hardware approval.** Turning on live access (ADR 0034) does not approve the agent sending these. Trying SET_LAYER or the RGB takeover on the user's Voyager needs the user's OK in chat for that category.

## Consequences
- Nothing in the app sends yet. Later slices build on this channel and test against FakeKeyboardLink, which records each session's commands, and FakeHID.
- `send` doesn't wait for the write. A write that fails shows in `connection` (the session ends), not as an error from `send`.
- Paired state is shared. A layer move from Sextant also moves the layer Oryx in Chrome or Keymapp shows, and either host's `05 00` ends the other's takeover. Pairing lasts until the board reboots (research 03 §3.5).
- If another host already paired the board, its events can reach Sextant during the handshake. `canSend` may then turn true before RawHIDLink's own pairing finishes (normally a few milliseconds later), and commands in that gap are dropped.
