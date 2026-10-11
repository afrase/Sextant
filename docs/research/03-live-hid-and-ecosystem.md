# 03 - Live host<->keyboard communication, Keymapp and its API, VIA/Vial alternatives, and the open-source landscape

Study date: 2026-10-11. Target: the user's ZSA Voyager, layout `KlgM7`, revision `40xJ7M`, firmware "25.0".
Audience: the engineer who will build the native macOS (Swift/SwiftUI) configurator.
Convention: every technical claim carries a source. **INFERRED** marks conclusions drawn from code or binaries rather than stated by a source.

**Revision 2 (same day).** The user asked us to also look at open-source information about the keyboard, and pointed to the Corne as a similar open keyboard. This revision adds:
- section 9: what about the Voyager is open, what the open firmware reveals about the hardware, other open firmwares for the Voyager, a Corne comparison, and open-source host apps to learn from;
- third-party hardware evidence for Keymapp's exclusive access (section 5.4) and for "no Input Monitoring prompt" (section 8.2);
- the MCU question, now resolved: there are two board variants, STM32 and GD32 (section 7.6).

---

## 0. Summary and recommendation

1. **The user's firmware speaks ZSA's "Oryx" raw-HID protocol, version 0x05.** The generated source enables it with `ORYX_ENABLE = yes` and the `zsa/oryx` community module. That module turns on `RAW_ENABLE` and forces `VIA_ENABLE` off. The interface uses vendor usage page `0xFF60`, usage `0x61`, 32-byte reports with no report ID, on USB interface #1 of VID `0x3297` PID `0x1977`. I confirmed the descriptor bytes in the compiled `.bin` (section 2).
2. **The protocol is small.** It has 13 command codes and 13 event codes. "Pairing" has been a no-op handshake since firmware 22: send `0x01` and the board replies with success plus the current layer. Once paired, the board streams **raw physical key down/up as matrix (col,row)** and **layer changes**. The host can set or unset layers, take over the RGB matrix per LED or for all LEDs, drive the 4 status LEDs, and nudge brightness. The protocol **cannot read or write the keymap.** There is no dynamic keymap in this firmware, so every remap still needs a recompile and reflash.
3. **Keymapp** is ZSA's closed-source desktop app: Go 1.23 + Wails v2 + grpc-go + `sstallion/go-hid` (hidapi). Its optional API is gRPC over a Unix socket on macOS, off by default. That API is a thin, **write-mostly** wrapper over the same Oryx commands: list, connect, set/unset layer, RGB, status LED, brightness and status. It has **no event stream**, so you get no key or layer events, only `current_layer` when polled.
4. **Exclusive access.** hidapi on macOS opens devices with `kIOHIDOptionsTypeSeizeDevice` by default, and Keymapp's binary does not link `SetOpenExclusive`. So **while Keymapp is connected to the board, no other process can open the raw-HID interface.** That includes your app and Chrome/Oryx. This was INFERRED from the binary in revision 1. Two independent open-source projects have since **observed it on real ZSA boards** (section 5.4). Chrome opens non-exclusively, so your app and Oryx in Chrome *can* share the interface.
5. **macOS permissions.** Opening the vendor-page interface does **not** trigger Input Monitoring (TCC). Apple's IOHIDFamily only requires TCC for devices that conform to GD Keyboard, GD Mouse or Digitizer TouchPad. Third-party Voyager and Moonlander tools report "no TCC prompt" on hardware. A sandboxed app needs `com.apple.security.device.usb`, which allows the `IOHIDLibUserClient` class.
6. **Recommendation.**
   - Make **direct raw HID the primary path**. Open non-exclusively, never seize, and match strictly on usage page `0xFF60` / usage `0x61` / VID `0x3297` / PID `0x1977`.
   - Treat Keymapp as a peer, not a dependency. Detect a "seized" state and tell the user to disconnect Keymapp. Optionally call Keymapp's `DisconnectKeyboard` RPC when its API is enabled.
   - Instant no-reflash remapping is only possible with **custom firmware flashed once** (VIA or Vial dynamic keymap). That firmware has to multiplex the Oryx live protocol with VIA on the one raw-HID interface, and it has to reimplement per-layer LED maps. Two community firmwares with live remapping exist for the Voyager, and neither keeps the Oryx protocol or the Navigator trackpad (section 7.2).
   - Structure the HID layer as **one 32-byte raw-HID transport with pluggable protocol drivers** (Oryx now; VIA/Vial later). The same VIA/Vial driver would then also serve a Corne or any other VIA/Vial board (section 9.3).
7. **What is open source (section 9.1).**
   - Open: the keyboard firmware (GPL-2.0: `zsa/qmk_firmware`, `zsa/qmk_modules`, upstream `qmk/qmk_firmware` `keyboards/zsa/voyager`), the generated source of every Oryx layout, and ZSA's CLI tools (kontroll MIT, wally MIT, zapp MIT + Commons Clause).
   - Closed: Oryx and its build service, Keymapp, and the Navigator companion app.
   - ZSA has published **no Voyager schematic or PCB files** (INFERRED from the 17 public repos of `github.com/zsa`). The GPL firmware still documents the hardware well (section 9.2).
8. **Corne comparison (section 9.3).**
   - The Corne (`foostan/crkbd`, hardware MIT + CC-BY-4.0) is the reference for the "instant remap" path. Its maker ships VIA and Vial firmware for Corne v4 and tells users to remap in VIA or Vial.
   - The Voyager can follow that path, but only by leaving Oryx firmware.
   - Architecturally the Voyager is *simpler* for dynamic keymaps. It has one MCU, with the right half on an I2C I/O expander. The Corne has one MCU per half, linked by a split transport, and each half is flashed separately.
9. **Prior art (section 9.4).**
   - At least eight open-source clients already speak the Oryx protocol directly. Two are Swift/IOHIDManager (`bogo/probe`, `vibewrks/zsa-overlay`).
   - `martinezooo/keyjitsu` (Rust, MIT, macOS-tested, active 2026-10) already does "Keymapp parity + local QMK build + flash" for the Voyager. It is the closest existing analogue of the planned app and worth studying before design.

---

## 1. Sources examined (pinned)

| Source | Version / commit | Local copy (under `scratchpad/downloads/`) |
|---|---|---|
| User's generated source + build log + .bin | zipUrl from `layout.json`, built 2026-09-16 | `layout-source-c/extracted/` |
| User's compiled firmware (hexUrl) | `zsa_voyager_KlgM7_40xJ7M_my-macos-layout-fork.bin`, 65,804 B | `layout-bin/firmware.bin`, `oryx-endpoints-check/` |
| `zsa/qmk_firmware` branch `firmware25` (default branch) | `93b2b9ec3368f86c5eb5a2e3f934049f8daef885` (2026-09-02) | `zsa-qmk_firmware-fw25/repo` (sparse) |
| `zsa/qmk_modules` (submodule `modules/zsa` pinned by fw25 to this exact commit) | `13890cd7856175de20798689d15ba6a46bf0c5c7` (2026-08-10) | `zsa-qmk_modules/repo` |
| Older oryx.c/h (fw21, fw22, fw23, fw24) | branches `firmware21..24` | `zsa-oryx-history/` |
| `zsa/kontroll` | `be6a3c6d887c33d6228458bee0b3ce55a8f975e6` (2025-02-22), latest release 1.0.4 | `kontroll/repo` |
| `zsa/zapp` | `a1be75837323001ad1ae8e5787d88cd33f2ccc46` (2026-07-09) | `zapp/zapp` |
| `zsa/USBDeviceSwift` (fork of `kylekyle/USBDeviceSwift`) | `6ba30a8b5a62a817dab6d1ea9d40f8e3c5c711b5` (2019-09-27) | `oss-zsa_USBDeviceSwift/repo` |
| Oryx web bundle | `https://configure.zsa.io/assets/index-xhNfd6BI.js` (fetched 2026-10-11; hash changes per deploy) | `oryx-frontend/` |
| zsa.io pages (privacy, training FAQ, keymapp, flash) | fetched 2026-10-11 | `zsa-site/` |
| Keymapp.app installed locally | 1.3.7, `/Applications/Keymapp.app`, TeamID V32BWKSNYH | read in place, never executed |
| `qmk/qmk_firmware` master | `7a1bbf37c5c07da4ea0a162bb139083a46ef40a1` | `qmk-voyager-kbjson/`, `oss-corne/qmk_*` |
| `vial-kb/vial-qmk` branch `vial` | `dd43959ae5c08d8a28d38a1acf7b04e86b14a344`; Voyager keymap at `46dcb78ddc` | `vial-qmk-core/`, `vial-voyager/`, `vial-qmk-vialrgb/`, `oss-corne/vial_*` |
| `the-via/keyboards` / `the-via/qmk_userspace_via` | `9e3e9f4aa9f50f9439fdebc747560f51aaf109a0` / `3e440ab72335c56041689a173ea53a512660b104` | `oss-corne/via_*` |
| `foostan/crkbd` / `foostan/kbd_firmware` | `63366fb7f51cf2a796462fdd90527e99dd126055` / `b38479ca28f3787a95cd1984022110482385e3bc` | `oss-corne/crkbd_*`, `oss-corne/kbd_firmware_*` |
| `jpds/rmk-zsa-voyager` (RMK firmware for Voyager) | `69527d634003f7e88fe4d7bfa84431ac5d8e4309` (2026-09-19) | `oss-jpds_rmk-zsa-voyager/repo` |
| `rmk-rs/rmk` main | `ac1339f216445f064db25563c3729dd0f89ff6b6` | `oss-rmk-files/` |
| `zmkfirmware/zmk` main (ZMK Studio docs) | `4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85` | `zmk-studio-docs/` |
| Oryx-protocol clients: `bogo/probe`, `vibewrks/zsa-overlay`, `angusjfw/hbz`, `monorkin/voyager-disco`, `martinezooo/keyjitsu` | `38ba6df`, `2892e2d`, `65531cd`, `1753694`, `a3c0d3b` | `oss-bogo_probe/`, `oss-vibewrks_zsa-overlay/`, `oss-oryx-hid-clients/` |
| Swift VIA clients: `hello-malek/micromap`, `travjunt/keyframe`, `FireBall1725/LayerLens` | `f9ed19e`, `b0722f7`, `a9b3455` | `oss-swift-hid-refs/` |
| `libusb/hidapi` master | `852cc68b8e0e4c7eba0815ef992951cd8b75c55b` | `hidapi-mac/` |
| `sstallion/go-hid` | `3879eca0960538df22249770709b4ac27c8550d2` | fetched via raw URL |
| Apple `IOHIDFamily` | `IOHIDFamily-2238.100.59` (`777ccd9698845aadf711e32d843c8c9b777431d9`) | `apple-iohidfamily/repo` (sparse) |
| Chromium `services/device/hid/hid_service_mac.cc` | `main` (2026-10-11) | `chromium-hid/` |
| macOS SDK headers (IOKit HID, CoreHID) | Xcode SDK `MacOSX27.0.sdk` | local |
| macOS App Sandbox profile | `/System/Library/Sandbox/Profiles/application.sb` (Darwin 27.0.0) | local |

Repository metadata (created / last push / stars / license) comes from the GitHub REST API, queried 2026-10-11.

---

## 2. What the user's firmware actually contains

### 2.1 Build configuration

| File (in source zip) | Relevant content | Meaning |
|---|---|---|
| `zsa_voyager_my-macos-layout-fork_source/rules.mk` | `ORYX_ENABLE = yes`, `RGB_MATRIX_CUSTOM_KB = yes`, `PRECISION_TRACKPAD_ENABLE = yes`, `PRECISION_TRACKPAD_DRIVER = navigator_trackpad`, `MOUSEKEY_ENABLE = no` | Oryx live protocol on. Custom RGB effect slot available, which is needed for host RGB takeover (section 3.4). Navigator trackpad module included. |
| `.../keymap.json` | `"modules": ["zsa/oryx", "zsa/navigator_trackpad", "zsa/defaults"]` | Firmware 25 moved the Oryx protocol into the community module `zsa/oryx` (`zsa/qmk_modules` README.md lines 5-11). |
| `.../config.h` | `#define SERIAL_NUMBER "KlgM7/40xJ7M"`, `LAYER_STATE_8BIT` | **The USB serial number string carries the layout and revision IDs.** At most 8 layers. |
| `.../keymap.c` lines 82-85 | `if (rawhid_state.rgb_control) { return false; }` inside `rgb_matrix_indicators_user` | When a host takes over RGB, the per-layer LED map is suppressed. |
| `build.log` lines 24-30, 60 | compiles `/qmk/modules/zsa/oryx/oryx.c`, `quantum/raw_hid.c`, `navigator_trackpad*.c`, `quantum/digitizer.c` | Confirms oryx + raw HID + PTP digitizer. **No `quantum/via.c` and no `dynamic_keymap.c`** (`grep` count 0). |
| `build.log` "Size after" | `.bin` = 65,786 bytes (0x100FA) | Firmware size. |
| `README.md` in the zip | "Congratulations on taking the next step, and making use of your keyboard's open-source nature!" Explains building against ZSA's fork or mainline QMK. | ZSA's own framing of the firmware as open source. |

Module to feature wiring:
- `zsa/qmk_modules` `oryx/qmk_module.json` lines 4-7: `"features": {"raw": true, "via": false}`.
- The QMK generator turns each pair into `<FEATURE>_ENABLE=yes|no`: `zsa/qmk_firmware@firmware25` `lib/python/qmk/cli/generate/community_modules.py` lines 134-140 and 165-168.
- `RAW_ENABLE` then adds `-DRAW_ENABLE`: `builddefs/common_features.mk` lines 655-656.
- The module's `oryx/config.h` lines 6-10 sets `RAW_USAGE_PAGE 0xFF60`, `RAW_USAGE_ID 0x61`, `ORYX_ENABLE`, `ORYX_CONFIGURATOR`. These equal QMK's defaults (`tmk_core/protocol/usb_descriptor_common.h` lines 48-54), which are also VIA's.

### 2.2 USB descriptors parsed from the compiled `zsa_voyager_KlgM7.bin`

I parsed these with `python3 -I` over the binary. Script: `scratchpad/scripts/cfgdesc.py`.

Device descriptor at file offset 0xF370: `12 01 00 02 00 00 00 40 97 32 77 19 01 00 01 02 03 01`. That is USB 2.0, EP0 64 bytes, **VID 0x3297, PID 0x1977**, bcdDevice 0x0001, iManufacturer=1, iProduct=2, iSerialNumber=3.

The string table contains UTF-16LE "ZSA Technology Labs" (0xF2D0), "Voyager" (0xF2BE) and "KlgM7/40xJ7M" (0xF2A2).

Configuration descriptor at 0xF2FC (116 bytes, 4 interfaces, bus-powered, 500 mA):

| If# | Class/Sub/Proto | Endpoints | Report desc len | Role |
|---|---|---|---|---|
| 0 | 03/01/01 (boot keyboard) | 0x81 IN, 8 B, 1 ms | 68 | Keyboard. Opening it requires TCC Input Monitoring (section 8.2). |
| **1** | **03/00/00** | **0x82 IN 32 B, 0x03 OUT 32 B, 1 ms** | **34** | **Raw HID (Oryx protocol)** |
| 2 | 03/00/00 | 0x84 IN, 32 B | 111 | Shared EP (NKRO, consumer, system, mouse) |
| 3 | 03/00/00 | 0x85 IN, 64 B | 380 | Digitizer / precision trackpad (Navigator) |

Raw HID report descriptor, found verbatim at 0xF382:

```
06 60 FF  09 61  A1 01          Usage Page 0xFF60, Usage 0x61, Collection(Application)
  09 62 15 00 26 FF 00 95 20 75 08 81 02   Input: 32 x 8-bit (data to host)
  09 63 15 00 26 FF 00 95 20 75 08 91 02   Output: 32 x 8-bit (data from host)
C0
```

Source of this layout: `zsa/qmk_firmware@firmware25` `tmk_core/protocol/usb_descriptor.c` lines 650-670 (report) and 789-837 (interface and endpoints). The interface is always #1 when RAW is on: `usb_descriptor.h` lines 153-166, where the comment says "If Raw HID is enabled, let it be always 1". `RAW_EPSIZE` is 32: `usb_descriptor.h` line 292.

Side note: the source has `HID_IOF_NON_VOLATILE` in the Output item, but the binary encodes `91 02`. This makes no difference to a host.

**There are no report IDs.** On macOS, use report ID 0 with exactly 32 data bytes. hidapi's `hid_write` instead needs a leading 0x00, which makes 33 bytes (also observed on hardware: `angusjfw/hbz` spec line 198, "leading 0x00 report id on write (macOS)").

The downloaded `.bin` (hexUrl) ends in **one** DFU suffix, at offset 0x100FC: VID 0x3297, PID 0x0791, bcdDFU 0x0100. 0x0791 is the Ignition bootloader on the **STM32** variant (section 7.6). I parsed it with `python3 -I`.

The live machine had no Voyager attached during this study. `hidutil list`, `system_profiler SPUSBDataType` and `ioreg -p IOUSB` showed no VID 0x3297. All descriptor facts above come from the firmware image.

---

## 3. The Oryx raw-HID protocol (firmware v25, protocol version 0x05)

Primary source: `zsa/qmk_modules@13890cd` `oryx/oryx.h` (96 lines) and `oryx/oryx.c` (360 lines). Line numbers below refer to these files. Both were re-read for revision 2 and match.

ZSA's own description (zsa.io/training FAQ, "Is this a keylogger?"): "The protocol only sends the physical positions of the keys being pressed." And under "Is it open-source?": "The code that runs on the keyboard is open-source … The server-side component is a part of Oryx, which is not open-source."

### 3.1 Transport and framing

| Property | Value | Source |
|---|---|---|
| HID usage page / usage | 0xFF60 / 0x61 | `oryx/config.h` lines 6-7 |
| Report size | 32 bytes both directions, no report ID | `oryx.h` lines 23-25; `usb_descriptor.c` 650-670 |
| Byte 0 | command (host->kb) or event (kb->host) | `oryx.h` lines 8-9 |
| Bytes 1..31 | params | `oryx.c` line 116 `param = &data[1]` |
| Stop marker | `ORYX_STOP_BIT -2`, written into `uint8_t`, so **0xFE** | `oryx.h` line 28 |
| Trailing bytes after the stop marker | **uninitialised stack garbage**. Event buffers are `uint8_t event[RAW_EPSIZE];` with no memset. | `oryx.c` lines 49, 57, 67, ... |
| Send path | `raw_hid_send_oryx` drops any length other than 32. If `send_report` fails, ChibiOS sets `paired=false`. | `oryx.c` lines 37-46 |
| Firmware send timeout | 100 ms per IN report; IN/OUT queues hold 4 reports | `tmk_core/protocol/chibios/usb_main.c` lines 458-460; `usb_endpoints.h` lines 8-9, 38-43 |
| Receive | `raw_hid_task` drains all queued OUT reports each main-loop pass | `usb_main.c` lines 593-598 |

Parsing rule for hosts (INFERRED from the code): read byte 0. For variable payloads, read up to the first 0xFE. For `EVT_RGB_CONTROL` (0x08) and `EVT_STATUS_LED_CONTROL` (0x0B) there is **no** stop byte, so read exactly byte 1. Never trust bytes past the documented payload. `vibewrks/zsa-overlay` README line 218 reached the same conclusion on hardware: "Trailing bytes after the `0xfe` terminator are undefined and ignored".

### 3.2 Gating flags

| Flag | Where set | Effect |
|---|---|---|
| `ORYX_ENABLE = yes` (rules.mk) | Oryx-generated `rules.mk` | Oryx build switch. The actual code comes from the module listed in `keymap.json`. |
| module `zsa/oryx` | `keymap.json` | Compiles `oryx.c`, defines `COMMUNITY_MODULE_ORYX_ENABLE=TRUE` (`community_modules.py` line 155), sets RAW on and VIA off |
| `RAW_ENABLE` | from module features | Creates USB interface #1 |
| `RGB_MATRIX_ENABLE` (Voyager `keyboard.json` features) and `RGB_MATRIX_CUSTOM_KB` (rules.mk) | | Required for `ORYX_RGB_CONTROL` / `SET_RGB_LED*` / `UPDATE_BRIGHTNESS`. Otherwise the board returns error 0x04. Takeover registers the custom effect `oryx_webhid_effect` (`oryx/rgb_matrix_kb.inc`). `oryx.c` lines 96-101, 162-199. |
| `COMMUNITY_MODULE_AUTOMOUSE_ENABLE` | module `zsa/automouse` | Required for 0x0B/0x0C. **Not in the user's build**, so the board replies with error 0xFF. |
| `STATUS_LED_1..4` | `keyboards/zsa/voyager/voyager.h` lines 14-17 | 4 status LEDs (index 0..3). Index 4 or 5 returns error 0x05. |
| `VOYAGER_USER_LEDS` | not set | When unset, status LEDs show the layer bits unless a host holds `status_led_control` (`voyager.c` lines 111-129) |

### 3.3 Commands (host -> keyboard)

Enum: `oryx.h` lines 30-45. Handler: `oryx.c` lines 114-316.

| ID | Name | Request bytes | Needs paired? | Response | Notes |
|---|---|---|---|---|---|
| 0x00 | `ORYX_CMD_GET_FW_VERSION` | `00` | no | `EVT 0x00` | Returns `SERIAL_NUMBER` (lines 119-132) |
| 0x01 | `ORYX_CMD_PAIRING_INIT` | `01` | no | `04 FE`, then `05 <layer> FE` | Sets `paired=true` immediately. **Falls through** into the 0x02 case and breaks (lines 144-148). |
| 0x02 | `ORYX_CMD_PAIRING_VALIDATE` | `02 ...` | no | none | No-op, "for backwards compatibility with older versions of Wally / Keymapp" (line 148) |
| 0x03 | `ORYX_CMD_DISCONNECT` | `03` | - | `FF FF` (unknown command) | **Not handled.** No case exists, so the default sends an error (line 313). There is no way to un-pair. |
| 0x04 | `ORYX_SET_LAYER` | `04 <on> <layer>` | **yes** | none directly; a `05` layer event follows if the layer changed | `on==0` gives `layer_off(layer)`; otherwise `layer_move(layer)`, which clears all other layers (lines 150-160) |
| 0x05 | `ORYX_RGB_CONTROL` | `05 <enable>` | no | `08 <rgb_control>` (no stop byte) | `0`: zero `webhid_leds[]`, `rgb_matrix_reload_from_eeprom()`, release control. `!=0`: switch to the custom effect and take control (lines 103-112, 162-176). |
| 0x06 | `ORYX_SET_RGB_LED` | `06 <led> <r> <g> <b>` | no | none | **`led` is not bounds-checked** (`webhid_leds[param[0]]`, line 180). The host must clamp to 0..51. Auto-takes control. |
| 0x07 | `ORYX_SET_STATUS_LED` | `07 <idx 0..5> <on>` | no | none, or `FF 05` if idx out of range | Sets `status_led_control=true` first (line 201) |
| 0x08 | `ORYX_UPDATE_BRIGHTNESS` | `08 <up>` | no | none | `up!=0` calls `rgb_matrix_increase_val_noeeprom()`, else decrease (lines 251-262). Not persisted. |
| 0x09 | `ORYX_SET_RGB_LED_ALL` | `09 <r> <g> <b>` | no | none | Fills all 52 entries and auto-takes control (lines 188-199) |
| 0x0A | `ORYX_STATUS_LED_CONTROL` | `0A <enable>` | no | `0B <state>` (no stop byte) | `0` turns all 4 LEDs off and releases them to firmware (lines 263-290) |
| 0x0B | `ORYX_SET_AUTOMOUSE` | `0B <dev> <en>` | no | `0C <trackball> <trackpad> FE`, or `FF FF` | Needs the automouse module (lines 291-298) |
| 0x0C | `ORYX_GET_AUTOMOUSE` | `0C` | no | same as above | lines 299-312 |
| 0xFE | `ORYX_GET_PROTOCOL_VERSION` | `FE` | no | `FE 05 FE` | lines 134-142 |
| other | - | | | `FF FF` | default branch, line 313 |

### 3.4 Events (keyboard -> host)

Enum: `oryx.h` lines 47-63.

| ID | Name | Payload | When sent |
|---|---|---|---|
| 0x00 | `EVT_GET_FW_VERSION` | `00 <ASCII serial, no NUL> FE`. For this board: `00 4B 6C 67 4D 37 2F 34 30 78 4A 37 4D FE`, i.e. "KlgM7/40xJ7M". | Reply to 0x00. `memcpy(event+1, SERIAL_NUMBER, sizeof)` then the stop byte overwrites the NUL (lines 121-128). |
| 0x01 | `EVT_PAIRING_INPUT` | (legacy) | Never sent by v25 |
| 0x02 | `EVT_PAIRING_KEY_INPUT` | (legacy) | Never sent by v25 |
| 0x03 | `EVT_PAIRING_FAILED` | `03 FE` | `pairing_failed_event()` exists (lines 65-71) but nothing in v25 calls it |
| 0x04 | `EVT_PAIRING_SUCCESS` | `04 FE` | After 0x01 (lines 73-80) |
| 0x05 | `EVT_LAYER` | `05 <highest active layer> FE` | After pairing, and on every change of `get_highest_layer(layer_state \| default_layer_state)` while paired (deduplicated; lines 55-63, 334-360) |
| 0x06 | `EVT_KEYDOWN` | `06 <col> <row> FE` | Every physical press while paired, from `pre_process_record` (before tap/hold resolution; lines 318-332) |
| 0x07 | `EVT_KEYUP` | `07 <col> <row> FE` | Every physical release while paired |
| 0x08 | `EVT_RGB_CONTROL` | `08 <0\|1>` | Reply to 0x05 |
| 0x09 | `EVT_TOGGLE_SMART_LAYER` | `09 FE` | `toggle_smart_layer()` exists (lines 82-87); no caller in fw25 or the modules (grep) |
| 0x0A | `EVT_TRIGGER_SMART_LAYER` | `0A FE` | `trigger_smart_layer()` (lines 89-94); no caller found |
| 0x0B | `EVT_STATUS_LED_CONTROL` | `0B <0\|1>` | Reply to 0x0A |
| 0x0C | `EVT_AUTOMOUSE` | `0C <tb> <tp> FE` | Reply to 0x0B / 0x0C |
| 0xFE | `EVT_GET_PROTOCOL_VERSION` | `FE 05 FE` | Reply to 0xFE |
| 0xFF | `EVT_ERROR` | `FF <code>` | See below |

Error codes (`oryx.h` lines 65-73): `00` PAIRING_INIT_FAILED, `01` PAIRING_INPUT_FAILED, `02` PAIRING_KEY_INPUT_FAILED, `03` PAIRING_FAILED, `04` RGB_MATRIX_NOT_ENABLED, `05` STATUS_LED_OUT_OF_RANGE, `FF` UNKNOWN_COMMAND.

### 3.5 Handshake and session semantics

- **Current handshake (fw22 onward):** `01` gives `04 FE`, then `05 <layer> FE`. There is no challenge.
  - fw21 used a real 3-key pairing stored in EEPROM: `firmware21` `quantum/oryx.c` lines 31-110, `PAIRING_SEQUENCE_SIZE 3` in `oryx.h` lines 14-18.
  - fw22 replaced it with immediate success: `firmware22` `quantum/oryx.c` lines 64-68. fw23 and fw24 are the same.
  - The `oryx.h` header comment (lines 11-14) still describes the old pairing-code scheme. It is stale.
- **Protocol versions:** fw22 0x02, fw23 0x04, fw24 0x04, fw25 module 0x05. 0x05 added automouse in `zsa/qmk_modules` commit `f8e012a` (2026-06-29). Sources: `firmware22/quantum/oryx.h` line 24, `firmware23/quantum/oryx.h` line 31, `firmware24/keyboards/zsa/common/oryx.h` line 27.
  - **Do not pin the version with an equality check.** `monorkin/voyager-disco` requires exactly 0x04 (`src/device.rs` lines 22, 108-112), so it refuses fw25 boards (INFERRED from the code). Accept a known range and gate features by version (automouse needs >= 0x05).
- **Paired state is global in firmware RAM** (`rawhid_state`, `oryx.c` lines 17-21). It is shared by every host that has the interface open. It resets only on reboot, or when an IN send fails on ChibiOS. A host should re-send `01` after every (re)open (INFERRED best practice).
- **Unpaired hosts can still** read the FW version and protocol version, and drive RGB and status LEDs. Only `SET_LAYER` and the outgoing key and layer events depend on `paired`.
- **Host-side throttling:**
  - Oryx web waits 1000 ms after every packet (section 4).
  - The firmware itself only needs reports not to overflow the 4-deep OUT queue between main-loop passes. Pacing at about 1 report/ms is fine (INFERRED from `raw_hid_task` and the 1 ms endpoint interval). An all-LED repaint of 52 reports takes about 52 ms.
  - `monorkin/voyager-disco` paces repeated brightness steps at 5 ms (`src/device.rs` lines 269-325).
  - Keymapp issue zsa/kontroll#19 reports crashes under sustained high-rate `set_rgb_led` through Keymapp's API.
- **Typing-latency hazard (INFERRED):** every key event while paired is a blocking `send_report` with a 100 ms timeout. In practice macOS's HID driver keeps polling the IN endpoint, so the queue does not fill. A host should still keep an input-report callback registered for as long as it holds the device open. `angusjfw/hbz` observed on hardware: "(col,row) streamed live during normal typing with zero interference" (spec line 195).
- **No held-key snapshot.** A key already held when the host pairs is invisible until its release event (`vibewrks/zsa-overlay` README lines 175-176).

### 3.6 Matrix position to Oryx key index to RGB LED index (Voyager)

The Voyager's Oryx key index (0..51, the order of the `keys` array in the layout JSON) equals:
- the `kNN` label order in `keyboards/zsa/voyager/keyboard.json` lines 162-215;
- the RGB LED index (`keyboard.json` rgb_matrix layout lines 102-155; `voyager.c` LED table lines 133-197).

Oryx web confirms both. It maps key events with table `jC[row][col]` (bundle offset 867,072, used in `handleKeyevent` at 878,879) and sends `SET_RGB_LED` with `led = keyIndex` for "voyager" (offset 869,950).

I also checked against the layout JSON: index 24 = `LT(1,KC_ENTER)` (left thumb) and index 51 = `LT(2,KC_SPACE)`.

`index = jC[row][col]` (-1 = no key):

| row \ col | 0 | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|---|---|
| 0 | - | 0 | 1 | 2 | 3 | 4 | 5 |
| 1 | - | 6 | 7 | 8 | 9 | 10 | 11 |
| 2 | - | 12 | 13 | 14 | 15 | 16 | 17 |
| 3 | - | 18 | 19 | 20 | 21 | 22 | - |
| 4 | - | - | - | - | 23 | - | - |
| 5 | 24 | 25 | - | - | - | - | - |
| 6 | 26 | 27 | 28 | 29 | 30 | 31 | - |
| 7 | 32 | 33 | 34 | 35 | 36 | 37 | - |
| 8 | 38 | 39 | 40 | 41 | 42 | 43 | - |
| 9 | - | 45 | 46 | 47 | 48 | 49 | - |
| 10 | - | - | 44 | - | - | - | - |
| 11 | - | - | - | - | - | 50 | 51 |

Indices 0-23 are the left 4 rows, 24-25 the left thumbs, 26-49 the right 4 rows, 50-51 the right thumbs. This matches `zsa/kontroll` `src/utils.rs` lines 11-36.

### 3.7 Firmware-side gotchas for the host implementer

1. `SET_RGB_LED` with `led >= 52` writes out of bounds (`oryx.c` line 180). **Always clamp.**
2. RGB takeover output is scaled by global brightness: `rgb * hsv.v/255` (`oryx/rgb_matrix_kb.inc` lines 9-12). `max_brightness` is capped at 175 (`keyboard.json` line 50). Observed on hardware: "At 50% brightness, `ff0000` appears as `7f0000`" (`monorkin/voyager-disco` README line 204; also `angusjfw/hbz` spec lines 199-203).
3. While `rgb_control` is set, the per-layer `ledmap` colours stop showing (`keymap.c` lines 82-85; `zsa/qmk_modules` `keycolors/keycolors.c` lines 37-41). **INFERRED:** your app can render per-layer colours live from the host.
4. Release RGB with `05 00`. That reloads the RGB mode from EEPROM. Host colours live in RAM only: they survive the app exiting but not a power cycle (`voyager-disco` README line 206). So **always send `05 00` on quit**, or the board keeps the app's colours.
5. Release status LEDs with `0A 00`. LEDs go dark until the next layer change, because `layer_state_set_kb` repaints only on layer changes (`voyager.c` lines 111-129).
6. `04 01 n` uses `layer_move`. It drops momentary layers and keeps the default layer. `04 00 n` is `layer_off`.
7. There is no keymap read/write in this protocol. To display the keymap, fetch the layout from Oryx GraphQL using the IDs in the serial number, which is what Oryx web and Keymapp do (sections 4 and 5). ZSA's privacy page confirms: "When Keymapp or Zapp needs to fetch a keyboard layout, it sends the layout's hash identifier (which is stored in your keyboard's firmware) to Oryx" (zsa.io/privacy).

### 3.8 Security note (for the threat model, not an exploit)

The interface needs no OS permission (section 8.2), and pairing has no challenge since fw22. **Any local process** can therefore receive every physical key press as (col,row) while paired. Combined with the public layout JSON (IDs from the USB serial), that is a keystroke-level side channel that bypasses macOS Input Monitoring.

This is inherent to ZSA's design. Your app should handle these events in memory only and say so in its privacy text. `angusjfw/hbz` makes the same point: "a paired listener receives every keypress position — effectively keystroke telemetry" (spec lines 216-218).

### 3.9 Example session (reconstructed from code; device not attached during this study)

```
H->K  00 00..00                         GET_FW_VERSION
K->H  00 4B 6C 67 4D 37 2F 34 30 78 4A 37 4D FE ..   "KlgM7/40xJ7M"
H->K  FE 00..                           GET_PROTOCOL_VERSION
K->H  FE 05 FE ..
H->K  01 00..                           PAIRING_INIT
K->H  04 FE ..                          PAIRING_SUCCESS
K->H  05 00 FE ..                       LAYER 0
(press top-left key: matrix row0 col1)
K->H  06 01 00 FE ..                    KEYDOWN col=1 row=0  -> index 0
K->H  07 01 00 FE ..                    KEYUP
H->K  04 01 02                          SET_LAYER move to 2
K->H  05 02 FE                          LAYER 2
H->K  05 01                             RGB_CONTROL on
K->H  08 01
H->K  06 00 FF 00 00                    LED 0 red
H->K  09 00 00 40                       all LEDs dim blue
H->K  05 00                             RGB_CONTROL off (restore)
K->H  08 00
H->K  07 00 01                          status LED 1 on (takes status-LED control)
H->K  0A 00                             release status LEDs
K->H  0B 00
```

Third-party hardware confirmation of the first half of this exchange: `vibewrks/zsa-overlay` README lines 204-213 lists the verified prefixes `fe 05 fe`, `04 fe`, `05 <layer> fe`, `06 <column> <row> fe` and `07 <column> <row> fe` (Moonlander, protocol 5). `angusjfw/hbz` (Voyager) records a `GET_FW_VERSION` round trip, `PAIRING_INIT` -> success + initial layer, `SET_RGB_LED` accepted and `RGB_CONTROL 0` acknowledged (spec lines 191-196).

---

## 4. How Oryx web uses the protocol (WebHID)

Source: `https://configure.zsa.io/assets/index-xhNfd6BI.js`, downloaded 2026-10-11. Character offsets are approximate and refer to that bundle.

| Aspect | Finding | Offset |
|---|---|---|
| Device filter | `{vendorId, productId, usage: 97 (0x61), usagePage: 65376 (0xFF60)}` for vendor IDs `[0xFEED, 0x3297]` × product IDs. Voyager = `6519` (0x1977); Moonlander = 0x1969, 0x1972; Planck EZ = 0x6060, 0xC6CE, 0xC6CF; ErgoDox = 0x1307, 0x4974-0x4976, 0x2010, 0x2020, 0x2030 | 770,693 (`Z7=65376`), `MC()` at 771,453 |
| Key counts per geometry | ergodox 76, planck 47, moonlander 72, **voyager 52**, halfmoon 36 | same |
| Connect / "pair" | `navigator.hid.requestDevice({filters})`, `open()`, register `inputreport` and `disconnect`. Then `sendPacket(0)` (GET_FW_VERSION). If `localStorage["pairing-<pid>"]` exists, `sendPacket(2, seq)`; else `sendPacket(1)` | 870,654 (`pair`) |
| sendPacket | 32-byte zero-filled array, `[cmd, ...params]`, `device.sendReport(0, bytes)`, then **sleep 1000 ms** | 869,323 |
| Input parsing | reads bytes as **Int8** and stops at `-2` (0xFE) | ~868,100 (handler `t`, before `case Dj` at 868,241) |
| Event handling | `0`: decode UTF-8, split on "/", `fetchLayout(layoutId, revisionId)`. `1`: map pairs to keys for pairing UI. `2`: advance pairing highlight. `3`: reset. `4`: `setPaired(true)`. `5`: `setCurrentLayer`. `6`/`7`: `handleKeyevent("down"/"up", col, row)`. `255`: log error | 868,241 onward |
| Commands used | `0` GET_FW_VERSION, `1` PAIRING_INIT, `2` PAIRING_VALIDATE, `5` RGB_CONTROL (`takeoverRgb`), `6` SET_RGB_LED (`setLedColor`, voyager index = key index), `7` SET_STATUS_LED (`toggleStatusLed`). Oryx web does **not** use SET_LAYER, brightness, SET_RGB_LED_ALL or the protocol-version query. | 869,323-870,600 |
| Live view, Train, heatmap | `handleKeyevent` maps `jC[row][col]` to `activeKeys[i]` and the heatmap (`setHeatmapStroke`). Sessions are timed and reported to the server via a `training` GraphQL mutation (seconds, protocol). | 878,879 (`handleKeyevent`), 877,957 (`training` event) |
| Legacy | A WebUSB (`navigator.usb`, `transferOut`) path still exists for old firmware (`flipProtocol`) | 883,877 |
| Linux note | ZSA's udev rules grant `hidraw` for VID 3297 "for Oryx web flashing and live training". Legacy WebUSB rules are "Not needed for firmware v21+". | `raw.githubusercontent.com/wiki/zsa/wally/Linux-install.md` |

ZSA blog: "Firmware 21 and up ... pairing requires you to hit a sequence of three random keys", with the sequence saved in browser local storage (`https://blog.zsa.io/2206-bye-oryx-key/`). On fw22+ the firmware skips that step (section 3.5). **INFERRED:** Oryx's stored-sequence path (`sendPacket(2, …)`) gets no reply from v25 firmware. Your app should always use `01`.

`zsa/qmk_modules` README.md lines 10-11 says the module serves "Oryx's live training / Keymapp live view / typ.ing live view". The training FAQ adds that typ.ing live view only works for layouts stored in Oryx, "since Oryx doesn't have a copy" of locally compiled layouts (zsa.io/training).

---

## 5. Keymapp

### 5.1 What it is

| Item | Value | Source |
|---|---|---|
| Purpose | Live on-screen layout view with layer tracking; always-on-top mini overlay; **Heatmap** of most-used keys per layer; **Smart Layers** (switch layer when an app becomes frontmost); flashing; shortcuts to Oryx edit and Live Training | `https://www.zsa.io/keymapp`; App Store description (iTunes lookup `bundleId=io.zsa.keymapp`); `https://blog.zsa.io/keymapp/` |
| ZSA's own summary | "Keymapp displays your live keymap, generates an on-device heat map of your keyboard use, and flashes firmware … It exposes a local API … only when you explicitly enable this API feature in Keymapp's settings (it is off by default). The heat map is processed strictly on your device" | zsa.io/privacy, "What These Applications Do" |
| Platforms | Windows, macOS, Ubuntu LTS 20.04+ (Linux needs gtk3, webkit2gtk-4.1, libusb and udev rules) | `https://blog.zsa.io/keymapp/`; Wally wiki Linux-install |
| macOS distribution | DMG `https://oryx.nyc3.cdn.digitaloceanspaces.com/keymapp/keymapp-latest.dmg` (Last-Modified 2025-05-19, 18,364,162 B). **Mac App Store** "ZSA Keymapp" `io.zsa.keymapp`, version 1.3.7, released 2025-05-19, min macOS 10.13, App Store id 6472865291 (sandboxed). | HTTP HEAD; `itunes.apple.com/lookup?bundleId=io.zsa.keymapp` |
| Windows note | Keymapp ships the driver Windows needs for flashing | `https://www.zsa.io/flash` |
| Open source? | No: "we will not be open-sourcing Keymapp" | `https://blog.zsa.io/keymapp/` |
| Local install | `/Applications/Keymapp.app`. `CFBundleShortVersionString` 1.3.7. Universal (x86_64 + arm64). Hardened runtime. **No entitlements** (DMG build, not sandboxed). `NSAllowsLocalNetworking`. Bundles `libusb-1.0.0.dylib` and a helper `Contents/MacOS/appwatch`. | `plutil`, `codesign -d`, `ls` (read-only) |
| Tech stack (INFERRED from binary strings) | `go1.23.4`, `github.com/wailsapp/wails/v2` (WebKit UI, Svelte Kit + Tailwind front end), `google.golang.org/grpc`, `github.com/sstallion/go-hid` (hidapi), `github.com/Khan/genqlient` (GraphQL client for Oryx), `github.com/marcinbor85/gohex` plus `[HALFKAY]`/`[DFU]` flashing strings, sqlite (migrated from goleveldb), `emersion/go-autostart` | `strings` on `Contents/MacOS/keymapp` |
| Local state | `~/Library/Application Support/.keymapp/keymapp.sqlite3`. Tables `config(key,value)`, `metadata`, `heatmap(revisionId, enabled, data)`, `revision(revisionId, data)` (cached layouts), `smart_layer(app, layer, layoutId, revisionId)`, `auth(token, username)`. Config keys: `api_enabled` (0 on this machine), `api_port` (50051), `startup_autoconnect` (0), `smart_layers_enabled` (1), `update_check`, `prompt_update_check`, `startup_minimized`. | `sqlite3 -readonly .schema` (values for auth tables not read) |
| Network endpoints in binary | `https://oryx.zsa.io` (GraphQL), `https://configure.zsa.io/keymapp-startup-data.json` (key catalog: 61 categories, 2,526 keys; copy in `downloads/keymapp-startup-data/`), `/train`, `/account/auth_phrase` (account link for private layouts) | `strings` |
| Telemetry | Keymapp, Kontroll, Zapp and the Navigator companion app "also perform: Update checks, Anonymous usage telemetry … Crash reporting" (self-hosted Sentry) | zsa.io/privacy |

**How Keymapp knows the layout (INFERRED).** It sends GET_FW_VERSION (or reads the USB serial), gets "layoutId/revisionId", fetches the revision from Oryx GraphQL and caches it in the `revision` table. `kontroll status` shows `firmware_version: "xxx/xxx"`, i.e. that same string (zsa/kontroll#16 maintainer reply). `vibewrks/zsa-overlay` reads that cache read-only to get legends (README lines 98-125), which shows the `revision` table is usable by third parties.

### 5.2 Keymapp API (what kontroll uses)

Proto: `zsa/kontroll@be6a3c6` `proto/keymapp.proto` (package `api`, `go_package github.com/zsa/keymapp/api`), service `KeyboardService` (lines 94-118). Re-read for revision 2; it matches.

| RPC | Request | Reply | Probable Oryx command (INFERRED) |
|---|---|---|---|
| `GetStatus` | `{}` | `{keymapp_version: string, connected_keyboard: {friendly_name, firmware_version, current_layer:int32}}` | cached FW-version string and last `EVT_LAYER` |
| `GetKeyboards` | `{}` | `{keyboards: [{id:int32, friendly_name, is_connected:bool}]}` | HID enumeration |
| `ConnectKeyboard` | `{id:int32}` | `{success}` | open device and `01` |
| `ConnectAnyKeyboard` | `{}` | `{success}` | same, first device |
| `DisconnectKeyboard` | `{}` | `{success}` | close HID handle |
| `SetLayer` | `{layer:int32}` | `{success}` | `04 01 <layer>` |
| `UnsetLayer` | `{layer:int32}` (same message) | `{success}` | `04 00 <layer>` |
| `SetRGBLed` | `{led, red, green, blue, sustain:int32}` | `{success}` | `06 led r g b` |
| `SetRGBAll` | `{red, green, blue, sustain}` | `{success}` | `09 r g b`. kontroll's "restore" sends `SetRGBAll(0,0,0,sustain=1)` (`src/api.rs` lines 304-326), probably mapped to `05 00`. |
| `SetStatusLed` | `{led, on:bool, sustain}` | `{success}` | `07 led on`. "restore" = `SetStatusLed(0,false,1)` (`api.rs` lines 356-377), probably `0A 00`. |
| `IncreaseBrightness` / `DecreaseBrightness` | `{}` | `{success}` | `08 01` / `08 00` |

- **Transport (macOS/Linux):** gRPC over HTTP/2 on a **Unix domain socket** at `$CONFIG_DIR/.keymapp/keymapp.sock`. On macOS that is `~/Library/Application Support/.keymapp/keymapp.sock`. For the App Store build it is `~/Library/Containers/io.zsa.keymapp/Data/Library/Application Support/.keymapp/keymapp.sock`. The `KEYMAPP_SOCKET` env var overrides it.
  - Sources: kontroll README.md lines 22-24; `src/api.rs` lines 89-104. kontroll dials a dummy authority `http://[::]:50051` over the UDS (line 115).
  - **Windows:** TCP `localhost:50051` (`KEYMAPP_PORT`), `api.rs` line 137.
- **Opt-in:** "In Keymapp's config page, make sure the API is enabled" (kontroll README line 22); requires Keymapp 1.3.2+ (same line). ZSA: "it is off by default" (zsa.io/privacy). On this Mac `api_enabled=0` and no socket exists.
- **`sustain` semantics are undocumented.** zsa/kontroll#9 "What is sustain?" has no answer.
- **No events.** There is no server-streaming RPC, so there are no key events, layer-change events or heatmap data. Layer must be polled through `GetStatus` (zsa/kontroll#16). Heatmap export is an open request (zsa/kontroll#14). `angusjfw/hbz` moved off this API for exactly this reason: "today we poll `GetStatus` at 100ms through two IPC hops" (spec lines 25-27).
- **Stability:** a high-rate `SetRGBLed` loop crashes Keymapp (zsa/kontroll#19, open).
- **Swift client:** feasible with `grpc/grpc-swift-2` (2.4.3) plus `grpc-swift-nio-transport` (2.10.0), which supports UDS targets (`Sources/GRPCNIOTransportCore/Client/Resolver/NameResolver+UDS.swift`). **INFERRED:** a sandboxed app cannot connect to a socket outside its container without a temporary-exception entitlement. Only a Developer-ID (non-sandboxed) build can use the Keymapp API.

### 5.3 Should a native app talk raw HID, rely on Keymapp, or both?

| Capability | Direct raw HID | Via Keymapp API |
|---|---|---|
| Key down/up stream (live view, heatmap, training) | yes | **no** |
| Layer change events | yes (push) | poll only |
| Read layout/revision IDs | yes (USB serial or `00`) | `GetStatus.firmware_version` |
| Set/unset layer, RGB, status LEDs, brightness | yes | yes |
| Works with Keymapp not installed | yes | no |
| Works while Keymapp is connected to the board | **no** (Keymapp seizes; section 5.4) | yes |
| Mac App Store / sandbox friendly | yes (`com.apple.security.device.usb`) | unlikely (UDS outside container; INFERRED) |
| Flashing | separate DFU path (other report) | no flashing RPC |

**Recommendation:**
- Implement the raw-HID client natively. Two projects in section 9.4 started on the Keymapp API and later moved to direct HID, for push events and to drop the Keymapp dependency: `vibewrks/zsa-overlay` (pre-cutover commit `c96521a`, README "Pre-cutover checkpoint") and `angusjfw/hbz` (spec lines 19-32).
- Detect the "seized by another client" condition: open returns `kIOReturnExclusiveAccess` (0xE00002C5), or CoreHID raises `.deviceSeized` or `HIDDeviceError.exclusiveAccess`. Show "Keymapp is connected to your Voyager".
- As an optional convenience, when `~/Library/Application Support/.keymapp/keymapp.sock` exists, call `DisconnectKeyboard` to release the board, and `ConnectAnyKeyboard` on exit.
- Do not build features on Keymapp's API: it lacks events and is closed and unversioned.

### 5.4 Exclusive device access when Keymapp is running

- hidapi's macOS backend initialises with `hid_darwin_set_open_exclusive(1); /* Backward compatibility */`. All later `hid_open*` calls therefore use `kIOHIDOptionsTypeSeizeDevice`.
  - Sources: `libusb/hidapi@852cc68` `mac/hid.c` line 476 and lines 1538-1541; `mac/hidapi_darwin.h` lines 52-66 ("By default on Darwin platform all devices opened by HIDAPI … are opened in exclusive mode").
  - go-hid vendors the same code: `sstallion/go-hid@3879eca` `hid_darwin.c` line 473 (hidapi 0.15.0). It exposes `SetOpenExclusive(bool)` in `hid_darwin.go`.
- Keymapp's binary links `go-hid.Init`, `Enumerate`, `OpenPath`, `OpenFirst`, `Exit` and `(*Device).Write/Read/...`. It contains **no `SetOpenExclusive`** symbol (0 occurrences). Go's linker drops unreferenced package functions.
  - **INFERRED, high confidence:** Keymapp opens the Voyager raw-HID interface **exclusively** while connected. `startup_autoconnect=0` on this Mac, so Keymapp only holds the device after the user clicks connect (or after `ConnectKeyboard` through the API).
- **Third-party hardware observations (new in revision 2):**
  - `angusjfw/hbz` (Voyager, fw25, macOS, Python and Rust hidapi): "exclusivity is real and mutual: with Keymapp connected, opening fails with `exclusive access and device already open` … `agent-deck pause` closes the device and Keymapp was connected again within a second" (`docs/specs/2026-08-04-direct-hid-renderer.md` lines 207-212 @`65531cd`).
  - `vibewrks/zsa-overlay` (Moonlander, protocol 5, Rust hidapi): maps `kIOReturnExclusiveAccess` `E00002C5` to "held by another process … quit or disconnect Keymapp" (`Sidecar/src/hid.rs` lines 26-27, 290-296 @`2892e2d`). Its README line 246 says runtime smoke tests covered "Keymapp/reader exclusivity".
  - `martinezooo/keyjitsu` README line 22: "Quit Keymapp before running keyjitsu. The raw HID channel is exclusive." `monorkin/voyager-disco` README line 203 says the same. `bogo/probe` README line 90 says Keymapp "may compete for the same Raw HID interface".
  - **Caveat:** all of these clients use hidapi, which also seizes, so the "mutual" exclusion they report is seize against seize. For a client that opens with `kIOHIDOptionsTypeNone`, two rows of the coexistence matrix below are confirmed and two remain INFERRED from IOHIDFamily source.
- IOKit semantics (Apple `IOHIDFamily-2238.100.59`; `handleOpen` re-read for revision 2):
  - `IOHIDDevice::handleOpen` lines 1211-1240: if another client already seized the device, `open` fails ("If seized, open returns failure but adds the client to _clientSet"). A new seizer messages existing clients with `kIOMessageServiceIsRequestingClose`.
  - `IOHIDLibUserClient::open` lines 700-725: the failed open returns **`kIOReturnExclusiveAccess`** and marks the client "seized".
  - While seized, `getReport` (line 1888) and `setReport` (line 1995) return `kIOReturnExclusiveAccess` ("Client is seized").
  - When the seizer closes, the others get `kIOMessageServiceWasClosed` and are un-seized (lines 860-880).
  - Seizing a *keyboard* nub needs a privileged client (lines 712-713). This does not apply to the vendor interface, and typing is never affected: interface 0 is a separate IOHIDDevice.
- Chrome (and so Oryx Live Training) opens with `kIOHIDOptionsTypeNone`: Chromium `services/device/hid/hid_service_mac.cc` line 175. Chrome and your app can therefore coexist.
- **Shared firmware state** across clients (INFERRED from `oryx.c`): `paired`, `rgb_control` and `status_led_control` are single globals. Two hosts drive the same LEDs, and either one's `05 00` releases the other's takeover. All open non-exclusive clients receive the same input reports.

Coexistence matrix:

| Already open | Then opened | Result | Status |
|---|---|---|---|
| Keymapp (seize) | Your app (none) | Your open gets `kIOReturnExclusiveAccess`; CoreHID reports seized. No I/O until Keymapp disconnects, then you are un-seized automatically. | Open failure **observed** on hardware (by hidapi clients); auto un-seize INFERRED |
| Your app (none) | Keymapp (seize) | Your client is forced into the seized state (calls fail with `kIOReturnExclusiveAccess`) until Keymapp closes | INFERRED (IOHIDFamily source) |
| Your app (none) | Chrome/Oryx (none) | Both work and both see the same events. Both can pair and both can drive LEDs. | INFERRED |
| Your app (**seize**) | Keymapp / Chrome | They fail. **Do not seize.** | **Observed** (hbz, zsa-overlay) |

---

## 6. Keymapp, Oryx and the firmware: who does what

- Oryx web compiles the firmware server-side. Download links come from the `hexUrl`/`zipUrl` in the revision. Live features run over WebHID.
- Keymapp flashes (HalfKay for Teensy, DFU for STM32 and the Voyager's "ignition" bootloader). It shows the live layout from the `00`/`05`/`06`/`07` stream and the cached GraphQL layout. Smart Layers come from an `appwatch` helper plus `04` SET_LAYER (INFERRED).
- zapp (ZSA's CLI flasher) fetches firmware by revision from `https://oryx.zsa.io/firmware/<revisionId>`, with `?alt=true` for "the board's alternate MCU" and `?collate=true` for a Moonlander collated image (`zsa/zapp@a1be758` `zapp-oryx/src/lib.rs` lines 21, 173-197).
- Voyager bootloader:
  - DFU VID:PID `3297:0791` on the STM32 variant and `3297:1791` on the GD32 variant (`zapp-core/src/device/ids.rs` lines 59-60, 86-87). App base `0x08002000` (`keyboards/zsa/voyager/rules.mk` lines 4-6).
  - `bootloader_jump` charges a capacitor on A8/A9 for 500 ms and resets. "The ignition bootloader is checking for a high signal on A8 for 100ms" (`voyager.c` lines 308-321).
  - Oryx web's DFU filters also list `0483:DF11` and `3297:{0x0791, 0x1791, 0x2000-0x2003}` (bundle offset 879,827, `b1`).
  - Flashing details belong to another report. They matter here only because "flash once" (section 7) uses this path.

---

## 7. Dynamic keymaps (VIA / Vial) and a "no-reflash instant remap" architecture

### 7.1 ZSA firmware status

- **Oryx-built firmware has no dynamic keymap and no VIA.**
  - The `zsa/oryx` module forces `"via": false` (`qmk_module.json` line 6).
  - The user's build compiles neither `via.c` nor `dynamic_keymap.c` (build.log).
  - The keymap is `const PROGMEM` (`keymap.c` line 19).
- The ZSA fork still contains upstream `quantum/via.c` and `quantum/dynamic_keymap.c`, so a custom build *can* enable VIA. The Oryx module and VIA **cannot simply be combined**:
  1. Both define a strong `raw_hid_receive()` (`oryx/oryx.c` line 114; `quantum/via.c` line 282), so the link fails.
  2. They share usage page 0xFF60/0x61 on the single raw interface.
  3. Command IDs collide. For example, `0x01` is Oryx PAIRING_INIT and VIA `id_get_protocol_version`. `0xFE` is Oryx protocol version and the Vial prefix.
  - Combining them needs a dispatcher. Options: VIA's `via_command_kb()` hook (`via.c` lines 278-292) claims Oryx traffic under a reserved ID, or the module's handler is renamed and called from that hook.
- Only Moonlander has official VIA support. `the-via/qmk_userspace_via` `keyboards/zsa/` contains only `moonlander` (keymap `via/rules.mk`: `VIA_ENABLE = yes`; last commit 2026-07-28). `the-via/keyboards` `v3/zsa/` holds only `moonlander.json`. **No official VIA definition exists for the Voyager.**
- Upstream QMK has the Voyager (`qmk/qmk_firmware@7a1bbf3` `keyboards/zsa/voyager`, `default` keymap only; last change 2025-01-20). A VIA build there is a three-line keymap (`VIA_ENABLE = yes`) plus a VIA definition JSON. It would have no Oryx protocol and no ZSA modules. INFERRED from the Corne's VIA keymap, `the-via/qmk_userspace_via@3e440ab` `keyboards/crkbd/keymaps/via/rules.mk` lines 1-3.

### 7.2 Community ports for the Voyager

| Project | Location | Status / last activity | Notes |
|---|---|---|---|
| **Vial (QMK)** (official vial-qmk tree) | `vial-kb/vial-qmk` branch `vial`, `keyboards/zsa/voyager/keymaps/vial/` (config.h, keymap.c, rules.mk, vial.json, readme.md) | Added in commit `46dcb78ddc` (2025-04-11, PR #869 by danielefongo). That is the only Vial-specific commit for this board (GitHub commits API on that path, 2026-10-11). The repo was last pushed 2026-07-26. | `VIA_ENABLE = yes`, `VIAL_ENABLE = yes`. UID `FD 2F 7F 8A 39 07 F7 DB`. Unlock combo = matrix (11,5)+(11,6), the two right thumb keys. `vial.json` has `"lighting": "none"`, so no RGB UI and no VialRGB. 3 default layers. Built on upstream `keyboards/zsa/voyager`, so it has **no Oryx protocol and no ZSA modules, hence no Navigator trackpad**. Its `vial.json` declares `vendorId 0x4c4b` / `productId 0x4643` (lines 3-4), but the keymap folder does not override the keyboard's `keyboard.json`. **INFERRED:** the board still enumerates as `3297:1977`, and the vial.json IDs are unused metadata, since Vial identifies boards by its own protocol and UID. Maturity: minimal, single contributor, no issues tracked. vial-qmk also has a `zsa/moonlander/keymaps/vial`. |
| **RMK (Rust) + Vial** | `jpds/rmk-zsa-voyager` (Apache-2.0 or MIT) | Created 2026-04-30 (first commit 2026-04-22), 40 commits, last push 2026-09-19, 7 stars | A full firmware replacement in Rust (RMK 0.9 + Embassy). "**Live keymap editing** via Vial - remap keys without reflashing" (README line 12). Six animated per-key RGB effects, a 4-bit layer display on the status LEDs, and chordal hold. Keymap stored in the last 4 KB of flash (`memory.x` lines 1-16). **USB IDs are RMK's defaults `0x4C4B:0x4643`, with serial `rmk:<version>`.** The port overrides only manufacturer and product name (`src/main.rs` lines 533-541; RMK defaults in `rmk-rs/rmk@ac1339f` `rmk/src/config/device.rs` lines 28-38; `vial.json` lines 3-4). Keymapp, Oryx and an Oryx-mode app will therefore not recognise it. `"lighting": "none"` (no VialRGB). No Oryx protocol and no trackpad. Flashed with `dfu-util -d 3297:0791 -a 0 -s 0x08002000:leave` (README line 55). Upstream RMK added a `zsa_voyager_bl` feature for the Ignition bootloader jump (`rmk-rs/rmk@ac1339f` `rmk/src/boot.rs` lines 12-31; `rmk/Cargo.toml` lines 244-245; `CHANGELOG.md` line 110). |
| VIA (QMK) | none found | - | GitHub repo and code searches ("voyager via", "zsa voyager vial", "zsa voyager firmware") returned only the two rows above plus personal QMK keymaps |
| ZMK | none found | - | The Voyager is a wired STM32/GD32 board. `joshyeram/zmk-config-voyager` (2023, 0 stars) is a user config, not a port. |

### 7.3 VIA protocol essentials (QMK `quantum/via.h` / `via.c` in `zsa/qmk_firmware@firmware25`)

- Same transport as Oryx: 32-byte reports on 0xFF60/0x61.
- The board **echoes the request buffer with fields filled in**. Unknown commands come back with byte 0 = `0xFF` (`via.c` lines 457, 464).
- `VIA_PROTOCOL_VERSION 0x000C` (`via.h` line 42).
- Multi-byte values are **big-endian**.

| ID | Name | Request | Response (bytes after id) | Source |
|---|---|---|---|---|
| 0x01 | get_protocol_version | `01` | `[1]=0x00 [2]=0x0C` | `via.c` 293-297 |
| 0x02 | get_keyboard_value | `02 <value_id>` | uptime(1), layout_options(2), firmware_version(4): u32 BE in bytes 2..5. switch_matrix_state(3): `02 03 <row_offset>` gives a row bitmap from byte 3 | `via.c` 298-351; `via.h` 79-85 |
| 0x03 | set_keyboard_value | `03 02 <u32 BE>` layout options; `03 05 <v>` device indication | echo | `via.c` 352-371 |
| 0x04 | dynamic_keymap_get_keycode | `04 <layer> <row> <col>` | bytes 4..5 = keycode BE | `via.c` 373-378 |
| 0x05 | dynamic_keymap_set_keycode | `05 <layer> <row> <col> <kc_hi> <kc_lo>` | echo | `via.c` 379-382 |
| 0x06 | dynamic_keymap_reset | `06` | echo | `via.c` 383-386 |
| 0x07/0x08/0x09 | custom set/get/save | `07 <channel> <value_id> <data…>`. Channel 3 = rgb_matrix: value 1 brightness (0-255 scaled to max), 2 effect (0 = off), 3 speed, 4 colour (H,S) | echo, get fills data | `via.c` 212-250, 640-718; `via.h` 87-113 |
| 0x0A | eeprom_reset | `0A` | only if `VIA_EEPROM_ALLOW_RESET` | `via.c` 393-399 |
| 0x0B | bootloader_jump | `0B` | **unhandled in upstream QMK** (returns 0xFF). Vial handles it only when unlocked (vial-qmk `quantum/via.c` lines 436-446). | `via.h` 65 |
| 0x0C | macro_get_count | `0C` | byte 1 = count (default 16) | `via.c` 400-403; `dynamic_keymap.h` 25-26 |
| 0x0D | macro_get_buffer_size | `0D` | bytes 1..2 = size BE | `via.c` 404-409 |
| 0x0E | macro_get_buffer | `0E <off_hi> <off_lo> <n<=28>` | data from byte 4 | `via.c` 410-415 |
| 0x0F | macro_set_buffer | `0F <off_hi> <off_lo> <n<=28> <data…>` | echo | `via.c` 416-421 |
| 0x10 | macro_reset | `10` | echo | |
| 0x11 | get_layer_count | `11` | byte 1 = `DYNAMIC_KEYMAP_LAYER_COUNT` (default 4) | `via.c` 426-429; `dynamic_keymap.h` 21-22 |
| 0x12 | get_buffer | `12 <off_hi> <off_lo> <n<=28>` | raw keymap bytes from byte 4 | `via.c` 430-435 |
| 0x13 | set_buffer | `13 <off_hi> <off_lo> <n<=28> <data…>` | echo | `via.c` 436-441 |
| 0x14/0x15 | get/set encoder | n/a on Voyager | | |

- **Keymap buffer layout** (`quantum/nvm/eeprom/nvm_dynamic_keymap.c` lines 80-98): `offset = layer*ROWS*COLS*2 + row*COLS*2 + col*2`, keycodes big-endian. For the Voyager (12×7) that is **168 bytes per layer**, including the unused matrix cells marked "-" in section 3.6.
- **Macro buffer:** NUL-separated strings. Prefix byte `0x01` (SS_QK_PREFIX) is followed by 1=tap, 2=down, 3=up, 4=delay (ASCII ms terminated by `|`) (`quantum/send_string/send_string_keycodes.h` lines 419-422).
- **Reflash resets the dynamic keymap.** VIA validates EEPROM with a magic derived from `QMK_BUILDDATE` (`via.c` lines 62-74). Every new firmware build therefore resets the dynamic keymap to the compiled defaults unless the build date is pinned. Plan the "flash once" UX around that.
- **VIA definition format (what a VIA/Vial-mode client consumes).** A JSON file with `name`, `vendorId`, `productId`, `matrix {rows, cols}`, optional `menus` / `keycodes` (lighting UI), and `layouts.keymap` in KLE (keyboard-layout-editor) format, where each key label is `"row,col"`. Examples: `the-via/keyboards@9e3e9f4` `v3/crkbd/crkbd.json` (Corne, 8×6, `menus: ["qmk_rgblight"]`); `foostan/kbd_firmware` `keyboards/crkbd/the-via/crkbd_rev4.json` (Corne v4, 8×7, `menus: ["qmk_rgb_matrix"]`); the Voyager Vial `vial.json` (12×7). For the Voyager the app already has a better geometry source in Oryx's metadata, so a definition only matters for compatibility with VIA/Vial apps.

### 7.4 Vial additions (vial-kb/vial-qmk@dd43959)

- All Vial commands are prefixed `0xFE` (`quantum/via.h` line 77; dispatch `via.c` lines 450-451). Sub-commands, from `quantum/vial.h` lines 37-62:
  - `00` get_keyboard_id: returns protocol version u32 LE (0x00000006) + 8-byte UID; byte 12 = VialRGB flag.
  - `01` get_size; `02` get_def. The definition is **LZMA/xz-compressed `vial.json`** (`util/vial_generate_definition.py` line 18). Apple's Compression framework (`COMPRESSION_LZMA`) can decode it.
  - `03`/`04` encoder; `05` unlock status, `06` unlock start, `07` unlock poll, `08` lock.
  - `09`-`0C` QMK settings query/get/set/reset.
  - `0D` dynamic entry op, with sub-ops: tap-dance get/set (10-byte entries: on_tap, on_hold, on_double_tap, on_tap_hold, tapping_term), combo get/set (4 inputs + output), key-override, alt-repeat.
- Entry counts scale with EEPROM size. Above 1000 bytes you get 8 tap dances and 8 combos; above 4000 bytes, 32 combos (`vial.h` lines ~80-120).
- Vial sets the USB serial to `"vial:f64c2b3c"` and turns on tap dance, combos, key overrides, caps word, layer lock, repeat key and QMK settings by default (`builddefs/build_vial.mk` lines 4-15).
- **VialRGB (per-LED host control under Vial; new in revision 2).** This is the closest Vial equivalent of Oryx's RGB takeover. It is carried in VIA's lighting commands, which vial-qmk routes to `vialrgb_get_value/set_value/save` when `VIALRGB_ENABLE` is set (vial-qmk `quantum/via.c` lines 310-370). Sources: `quantum/vialrgb.h` lines 7-22 and `quantum/vialrgb.c` lines 90-182, @`dd43959`.

  | Request | Meaning |
  |---|---|
  | `08 40` | get_info, which returns protocol version u16 LE (=1) and max brightness |
  | `08 41` | get_mode, which returns mode u16 LE, speed, H, S, V |
  | `08 42 <gt lo> <gt hi>` | list supported mode IDs greater than `gt` |
  | `08 43` | number of LEDs (u16 LE) |
  | `08 44 <led lo> <led hi>` | x, y, flags, matrix row, matrix col of one LED |
  | `07 41 <mode lo> <mode hi> <speed> <H> <S> <V>` | set mode (not saved). **Mode 1 = `VIALRGB_EFFECT_DIRECT`** (`vialrgb_effects.inc` lines 4-6). |
  | `07 42 <first lo> <first hi> <n≤9> (H S V)×n` | direct fast-set, **HSV, not RGB**. V is clamped to max brightness. Colours are kept in RAM (`g_direct_mode_colors`). |
  | `09` | save (`eeconfig_force_flush_rgb_matrix`) |

  - The Voyager's 52 LEDs need 6 fast-set packets.
  - VialRGB requires `VIALRGB_ENABLE` with `RGB_MATRIX_ENABLE`, and `"lighting": "vialrgb"` in `vial.json`. Both Voyager Vial ports currently use `"lighting": "none"`.

### 7.5 Telling firmwares apart without side effects

1. **USB VID:PID and serial number** (`kIOHIDSerialNumberKey`; no I/O needed):
   - Oryx builds use `3297:1977` and serial `<layoutId>/<revisionId>`, e.g. `KlgM7/40xJ7M` (config.h). Self-compiled builds without a serial get `default/latest` (`zsa/qmk_modules` `defaults/post_config.h` lines 8-10). keyjitsu-built firmware extends the serial with a local state id (keyjitsu README lines 144-160).
   - Vial (QMK) uses serial `vial:f64c2b3c`. The vial-qmk Voyager port most likely keeps `3297:1977` (INFERRED; section 7.2).
   - RMK's Voyager port uses `4C4B:4643`, manufacturer "RMK" and serial `rmk:<version>` (section 7.2).
2. If that is inconclusive, **probe with `FE 00 …`** (INFERRED from the code):
   - Oryx replies `FE 05 FE`.
   - Vial replies with 4-byte LE protocol version + UID.
   - Plain VIA echoes with byte 0 = `FF`.
   - **Never probe with `01`.** On Oryx that is PAIRING_INIT and starts the key-event stream.

### 7.6 EEPROM and flash budget on the Voyager MCU

| Item | Value | Source |
|---|---|---|
| MCU | **Two board variants: STM32F303 and GD32F303.** zapp names the Ignition bootloader "Voyager (Ignition STM32)" at `3297:0791` and "Voyager (Ignition GD32)" at `3297:1791`. It also handles a "Dual-firmware file (e.g., Ignition Voyager STM32+GD32)" made of two concatenated DFU images. The RMK port author says the board "ships with a GD32F303CB microcontroller (STM32F303CB-compatible)". QMK metadata says only "STM32F303" (readme: "STM32F303xC"). The linker script is "STM32F303xB memory setup", 128 KB. | `zsa/zapp@a1be758` `zapp-core/src/device/ids.rs` lines 37-40, 59-60, 86-87; `zapp-core/src/firmware/mod.rs` lines 14-19; `jpds/rmk-zsa-voyager` README line 5, `memory.x` lines 1-16; `keyboards/zsa/voyager/keyboard.json` line 6, `readme.md` line 6, `ld/voyager.ld` lines 17-30 |
| Which variant the user has | **Unknown.** The user's hexUrl `.bin` is the STM32 (`0791`) image (section 2.2). Oryx serves the other one with `?alt=true` (section 6). The board shows its variant only in bootloader mode, by PID. | INFERRED |
| App flash window | `0x08002000`, length 0x1E000 = **120 KB** (first 8 KB = ignition bootloader). RMK confirms 128 KB total and 8 KB bootloader. | `ld/voyager.ld` line 22; RMK `memory.x` line 13 |
| RAM | 32 KB (+ 8 KB CCM at 0x10000000, unused by the linker regions) | `ld/voyager.ld` lines 30, 34; RMK `memory.x` lines 4, 15 |
| Current firmware size | 65,786 B, so **~54 KB headroom** within the 120 KB window | build.log |
| EEPROM | **emulated in flash** (wear leveling, embedded-flash driver; `eeprom_wear_leveling.c` and `wear_leveling_efl.c` compiled). Defaults: `WEAR_LEVELING_BACKING_SIZE 2048`, `WEAR_LEVELING_LOGICAL_SIZE` = backing/2 = **1024 B**. Placed at the end of *physical* flash, detected at runtime from the flash-size register. | build.log; `platforms/chibios/drivers/wear_leveling/wear_leveling_efl_config.h` lines 48-56; `wear_leveling_efl.c` lines 28-46; `platforms/eeprom.h` lines 39-41 |
| EECONFIG core | `eeprom_core_t` (packed) = **37 B** (computed from the field list), plus 0 kb/user datablock | `quantum/nvm/eeprom/nvm_eeprom_eeconfig_internal.h` lines 12-33, 55-61 |
| VIA header | magic 3 B + layout options 1 B (+ custom 0), so `VIA_EEPROM_CONFIG_END` = 41 | `nvm_eeprom_via_internal.h` lines 11-22; `via.h` lines 24-38 |
| Dynamic keymap | 168 B/layer. A build fails unless at least 100 B remain for macros. | `nvm_dynamic_keymap.c` lines 20-69 |

Budget arithmetic (INFERRED from the formulas above):
- **Default 1 KB logical EEPROM:** 1024 - 41 = 983 B free. 4 layers (672 B) leaves 311 B of macros. Maximum 5 layers (840 B), leaving 143 B of macros.
- Vial's tap dances, combos and key overrides also come out of this space.
- **Increase `WEAR_LEVELING_BACKING_SIZE` to 8192:** logical 4096 B, 8 layers = 1,344 B, leaving ~2.7 KB for macros and Vial entries. This costs 8 KB of flash, which fits in the ~54 KB headroom.
- STM32F3 flash pages are 2 KB. Wear leveling stretches the ~10k-cycle endurance. The RMK port uses the last two 2 KB sectors the same way (`memory.x` lines 6-9).

### 7.7 What "no-reflash instant remap" would require

**Architecture (flash once):**
1. Build custom firmware from `zsa/qmk_firmware@firmware25` + `modules/zsa`, with `VIA_ENABLE=yes` (optionally Vial).
2. Increase the wear-leveling size (section 7.6).
3. Keep `zsa/navigator_trackpad` and `zsa/defaults`.
4. Port the Oryx live protocol into a `via_command_kb()` dispatcher, or reserve an unused VIA top-level ID or custom channel 0 for it.
5. Pin `QMK_BUILDDATE` or handle EEPROM reset on reflash.
6. **Build for the right MCU variant.** Produce both an STM32 and a GD32 image (as Oryx does), or detect the bootloader PID (`0791` or `1791`) before flashing. What differs between Oryx's standard and `?alt=true` builds is not visible in the public fork: there are no GD32 references under `keyboards/zsa/` at fw25. That makes this an open question (section 10).
7. Flash once via DFU (`3297:0791` or `3297:1791`).

After that, every keycode edit is a few 32-byte reports: `05` per key, or `13` buffer writes. It persists in EEPROM and takes effect immediately.

The two existing ports (section 7.2) prove that the MCU and bootloader support this model. Both took the simpler route of dropping Oryx entirely, and that is what the table below costs.

**Oryx features: fate under VIA / Vial** (mapping is INFERRED unless cited):

| Oryx feature (seen in user's layout or Oryx) | Plain VIA | Vial | Firmware work needed |
|---|---|---|---|
| Basic keycodes, MT/LT/OSM/OSL/TG/TO/MO/layer-tap | yes (16-bit keycodes) | yes | none |
| Custom "dual function" key `DUAL_FUNC_0 = LT(15, KC_1)` + `process_record_user` (tap `=`, hold `Esc`) (`keymap.c` lines 17, 130-144) | no (hold must be a layer or mod) | yes, as tap-dance on_tap/on_hold | or compile fixed custom keycodes into the firmware |
| Custom keycodes `RGB_SLD`, `HSV_0_255_255`… (`keymap.c` lines 8-13, 145-167) and ZSA `TOGGLE_LAYER_COLOR`, `LED_LEVEL` (`defaults/defaults.h` lines 7-11) | only if compiled in and exposed as `QK_KB`/`QK_USER` codes | same | keep them in firmware |
| Tap dance (Oryx tap / hold / double-tap / tap-hold) | no | yes (same 4 actions + per-entry term; `vial.h` lines 93-99) | none with Vial |
| Combos | no | yes (4-key input) | none with Vial |
| Macros | yes (buffer, delays) | yes | none |
| Per-key tapping term | no | partial (global QMK setting + per-tap-dance term) | custom per-key table |
| **Per-layer RGB key colours (`ledmap`)** (`keymap.c` lines 59-80) | **no** | **no** (VialRGB is effect/direct only; Voyager vial.json has lighting "none") | **reimplement**: store 52×3 B per layer (156 B/layer) in EEPROM via a custom VIA channel, or drive from the host with `RGB_CONTROL` / VialRGB direct mode while the app runs |
| RGB effect, speed, colour, brightness | yes (channel 3) | VialRGB if enabled | enable `VIALRGB_ENABLE` or VIA lighting |
| Status LED layer indicator, `LED_LEVEL` | firmware (unchanged) | same | none |
| Oryx live protocol (Keymapp live view, Oryx Train, typ.ing) | **lost** unless multiplexed | lost unless multiplexed | dispatcher (section 7.1) |
| Keymapp layout display | **broken**: serial no longer `layout/revision` and the layout is no longer in Oryx | same | your app becomes the source of truth |
| Navigator trackpad (PTP digitizer) | only if built from the ZSA fork + modules | the vial-qmk and RMK Voyager ports do **not** include it | build from ZSA tree |
| Caps word, auto shift, layer lock, key overrides | compile-time | yes (QMK settings / dynamic) | none with Vial |
| Smart Layers | host-side | host-side | your app: `SET_LAYER` on frontmost-app change |

**A middle path that keeps stock Oryx firmware: local build + reflash.** `martinezooo/keyjitsu` keeps the Oryx protocol and avoids custom flash-once firmware. It fetches the layout's generated source from Oryx, patches the keymap locally (including generated tap dances), compiles with a local QMK toolchain against `zsa/qmk_firmware -b firmware25`, and flashes with `zapp-core` (README lines 127-161). Remaps still need a reflash, but not Oryx's cloud. Prerequisites are about 2 GB of QMK plus an ARM GCC toolchain (README lines 131-137). This belongs to the build/flash report. It is noted here as the alternative to dynamic keymaps.

---

## 8. macOS HID specifics for the Swift app

### 8.1 Matching (IOHIDManager, macOS 10.5+)

```swift
let match: [String: Any] = [
  kIOHIDVendorIDKey:          0x3297,
  kIOHIDProductIDKey:         0x1977,   // add 0x1969/0x1972 etc. for other ZSA boards if desired
  kIOHIDPrimaryUsagePageKey:  0xFF60,
  kIOHIDPrimaryUsageKey:      0x61,
]
IOHIDManagerSetDeviceMatching(mgr, match as CFDictionary)
// open each matched IOHIDDevice with kIOHIDOptionsTypeNone (NOT SeizeDevice)
// IOHIDDeviceRegisterInputReportCallback(dev, buf32, 32, cb, ctx)   // 32-byte input, no report ID
// IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, 0, bytes, 32)    // report ID 0, exactly 32 bytes
// read serial: IOHIDDeviceGetProperty(dev, kIOHIDSerialNumberKey) -> "KlgM7/40xJ7M"
```

- Keys: `kIOHIDPrimaryUsagePageKey` and `kIOHIDSerialNumberKey` are in SDK `IOKit/hid/IOHIDDeviceKeys.h` lines 82 and 142. `kIOHIDOptionsTypeNone`/`SeizeDevice` are in `IOHIDKeys.h` lines 230-245.
- Use `IOHIDDeviceSetDispatchQueue` + `IOHIDDeviceActivate` (`IOHIDDevice.h` lines 233-290) to keep I/O off the main thread.
- Do **not** call `IOHIDManagerOpen` with broad matching. Opening keyboard or trackpad interfaces triggers TCC (section 8.2).
- **Working open-source Swift code with exactly this shape:**
  - `bogo/probe@38ba6df` `Apps/Probe/Sources/RawHIDMonitor.swift`: matching dict lines 96-101; `IOHIDManagerCreate`/`IOHIDManagerOpen` with `kIOHIDOptionsTypeNone` lines 91, 121; `IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, ptr, 32)` lines 222-238. It targets the Voyager with stock Oryx firmware and is MIT.
  - `travjunt/keyframe` (`Sources/Keyframe/HIDRawTransport.swift` line 36) and `FireBall1725/LayerLens` (`Sources/LayerLensCore/HID/HIDDevice.swift` line 43) use `IOHIDDeviceOpen(device, kIOHIDOptionsTypeNone)` for VIA boards.

**CoreHID alternative (macOS 15+, Swift-native, async):** SDK `CoreHID.framework` swiftinterface:
- `HIDDeviceManager.monitorNotifications(matchingCriteria:)` with `DeviceMatchingCriteria(primaryUsage: HIDUsage(page: 0xFF60, usage: 0x61), vendorID: 0x3297, productID: 0x1977)` (lines 176-199).
- `HIDDeviceClient(deviceReference:)`, `monitorNotifications(reportIDsToMonitor:elementsToMonitor:)`. Notifications include `.inputReport(id:data:timestamp:)` and **`.deviceSeized` / `.deviceUnseized`**, which detect Keymapp directly.
- `dispatchSetReportRequest(type: .output, id: nil, data:)`, `seizeDevice()` (avoid it), and `HIDDeviceError.exclusiveAccess` (lines 3494-3586).
- `HIDReportID` is a failable `init?(rawValue: UInt8)`. **INFERRED:** pass `id: nil` for this report-ID-less interface and monitor `HIDReportID.allReports`.
- Choose CoreHID if the deployment target is macOS 15+. Otherwise use IOKit. None of the surveyed open-source projects uses CoreHID yet, so it has no field evidence with ZSA boards.

### 8.2 Input Monitoring (TCC)

Primary source: Apple `IOHIDFamily-2238.100.59`.
- `IOHIDFamily/IOHIDDevice.cpp` lines 527-531: the kernel sets `kIOHIDRequiresTCCAuthorizationKey = true` **only** if the device `conformsTo(GenericDesktop, Keyboard) || conformsTo(GenericDesktop, Mouse) || conformsTo(Digitizer, TouchPad)`.
- `IOHIDLib/IOHIDDeviceClass.m` lines 511-535: `IOHIDDeviceOpen` calls `IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)` only when that property is YES. Otherwise it treats access as granted.
- SDK `IOKit/hidsystem/IOHIDLib.h` lines 143-210 documents `kIOHIDRequestTypeListenEvent` / `IOHIDCheckAccess` / `IOHIDRequestAccess` (macOS 10.15+).

**Field evidence (new in revision 2):**
- `angusjfw/hbz`: Voyager "opened with **no TCC prompt**" (spec lines 191-193).
- `vibewrks/zsa-overlay` README line 46: "The direct raw-HID interface did not require Input Monitoring or Accessibility permission on the tested Mac."
- `travjunt/keyframe` README line 20, a VIA board: "without requesting Accessibility or Input Monitoring access".

So:

| Voyager interface | Usage | TCC Input Monitoring? |
|---|---|---|
| #0 keyboard | GD/Keyboard | **yes** |
| **#1 raw (Oryx/VIA)** | **0xFF60/0x61** | **no** (source + field evidence) |
| #2 shared (NKRO/consumer/mouse) | contains GD/Mouse / keyboard collections | yes (INFERRED: conforms to keyboard/mouse) |
| #3 Navigator digitizer | Digitizer/TouchPad | yes |

### 8.3 App Sandbox entitlements

- macOS `/System/Library/Sandbox/Profiles/application.sb` (Darwin 27) lines 115-118: `(when (or (entitlement "com.apple.security.device.hid") (entitlement "com.apple.security.device.usb")) (allow iokit-open-user-client (iokit-user-client-class "IOHIDLibUserClient")))`.
- Lines 119-123 additionally allow `IOUSBDeviceUserClientV2`/`IOUSBInterfaceUserClientV3` (needed for DFU flashing) with `device.usb` only.
- `com.apple.security.device.usb` is the documented key ("Use this key to allow your sandboxed app to interact with USB devices"; developer.apple.com, documentation/bundleresources/entitlements/com.apple.security.device.usb). `device.hid` is undocumented (Apple Developer Forums thread 127670, unanswered).
- Supporting evidence:
  - The Mac App Store build of Keymapp (`io.zsa.keymapp`) is sandboxed (its socket lives in `~/Library/Containers/io.zsa.keymapp/…`, zsa/kontroll#15) and still talks HID and DFU.
  - `hello-malek/micromap@f9ed19e` `App/MicroMap.entitlements` lines 5-8 is a Swift VIA raw-HID configurator that ships exactly `com.apple.security.app-sandbox` + `com.apple.security.device.usb`.
- A non-sandboxed Developer-ID app with hardened runtime needs no HID entitlement. The DMG Keymapp has no entitlements at all (`codesign -d --entitlements`). `bogo/probe`'s entitlements contain only `com.apple.security.cs.disable-library-validation` (`Apps/Probe/Probe.entitlements`).

### 8.4 Multiple clients

See section 5.4. Summary:
- Non-exclusive opens coexist, and all receive input reports.
- A seize blocks everyone else (`kIOReturnExclusiveAccess`) until the seizer closes, after which the others are un-seized automatically.
- Seizing the vendor interface does not affect typing.
- Any hidapi-based tool (Keymapp, kontroll-adjacent Rust/Python tools) seizes by default. Expect "busy" from them while your app holds the interface only if your app seizes. It should not.

---

## 9. Open-source landscape: the Voyager, the Corne, and reusable host code

The user asked to look for open-source information about the keyboard, noting that the Corne is open source and similar. This section answers that from the angle of this report: live HID, dynamic keymaps and host software.

### 9.1 What about the Voyager stack is open

| Component | Open? | License | Source / evidence |
|---|---|---|---|
| Keyboard firmware (ZSA's QMK fork) | yes | GPL-2.0 | `github.com/zsa/qmk_firmware`, default branch `firmware25`; zsa.io/training: "The code that runs on the keyboard is open-source" |
| Oryx protocol module, trackpad, keycolors, defaults, automouse… | yes | GPL-2.0 | `github.com/zsa/qmk_modules` (README lines 1-12; `navigator_trackpad/qmk_module.json` "GPL-2.0-or-later") |
| Voyager keyboard definition in mainline QMK | yes | GPL-2.0 | `qmk/qmk_firmware@7a1bbf3` `keyboards/zsa/voyager` (maintainers drashna and ZSA, `readme.md` line 5) |
| Generated source of every Oryx layout | yes (download "Source" in Oryx, or `zipUrl`) | GPL (derived work) | user's zip `README.md`: "making use of your keyboard's open-source nature" |
| kontroll (Keymapp API CLI) | yes | MIT | `zsa/kontroll` |
| zapp (CLI flasher; crates `zapp-core`, `zapp-oryx`) | source-available | MIT **+ Commons Clause** ("does not grant … the right to Sell the Software") | `zsa/zapp` `LICENSE.md` lines 1-13 |
| wally / wally-cli (legacy flasher, Go + Wails) | yes | MIT | `zsa/wally` `license.md` |
| oryx-with-custom-qmk (GitHub Actions template) | yes | MIT | `zsa/oryx-with-custom-qmk` |
| USBDeviceSwift | yes; stale 2019 fork of `kylekyle/USBDeviceSwift` | MIT | `zsa/USBDeviceSwift@6ba30a8`. It is an IOHIDManager wrapper (`HIDDeviceMonitor.swift` lines 24, 31 use `kIOHIDOptionsTypeNone`). Its purpose for ZSA is undocumented, and it is not worth depending on. |
| Oryx (web configurator + compile service + GraphQL) | **no** | - | zsa.io/training: "The server-side component is a part of Oryx, which is not open-source." |
| Keymapp | **no** | - | blog.zsa.io/keymapp: "we will not be open-sourcing Keymapp" |
| Navigator companion app (macOS) | **no** (not on GitHub) | - | zsa.io/privacy: "a macOS utility that enables precision gestures and provides control over the behavior of the Navigator Trackpad"; "Kontroll and Zapp are open source" (Keymapp and the companion app are not listed as such) |
| Voyager hardware design (schematic, PCB, case) | **not published** | - | none of the 17 public repos in `github.com/zsa` (GitHub API, 2026-10-11) is a hardware repo; INFERRED |

### 9.2 Hardware facts recoverable from the open firmware

| Fact | Value | Source |
|---|---|---|
| Topology | **One MCU, in the left half.** The right half has no MCU: an MCP23018 I/O expander scans it over I2C through the inter-half cable. | `keyboards/zsa/voyager/matrix.c` lines 13-57 (`raw_matrix_right`, `mcp23018_init_local`); `rules.mk` lines 9-10 |
| MCU | STM32F303 or GD32F303 variant, 72 MHz (8 MHz HSE × 9) | section 7.6; RMK port `src/main.rs` lines 441-456 |
| Matrix | 12 rows × 7 cols, `ROW2COL`. Rows 0-5 left, 6-11 right (`MCP_ROWS_PER_HAND = MATRIX_ROWS/2`). | `config.h` lines 7-8; `keyboard.json` line 29; `matrix.c` line 17 |
| Left-half scan | direct GPIO: outputs B10-B15, inputs A0, A1, A2, A3, A6, A7, B0 | `matrix.c` lines 59-75; RMK `src/main.rs` lines 526-531 |
| I2C bus | I2C1 on B6 (SCL) / B7 (SDA); RMK runs it at 400 kHz | `matrix.c` lines 46-50; `mcuconf.h` lines 21-23; RMK `src/main.rs` lines 505-512 |
| RGB | 2 × IS31FL3731 on the same I2C bus (address pins GND / VCC), 52 LEDs, `max_brightness` 175 | `config.h` lines 12-15; `keyboard.json` lines 46-50 |
| Status LEDs | 4: LED1 = B5, LED2 = B4 (left GPIO), LED3/LED4 = MCP23018 outputs (`mcp23018_leds[0..1]`) | `voyager.h` lines 14-17; RMK `src/main.rs` lines 116-128 (port B bits 7/6, active low) |
| MCP23018 reset | B8, active low (RMK) | RMK `src/main.rs` lines 499-503 |
| Bootloader | ZSA "Ignition" DFU in the first 8 KB; app at 0x08002000; entered by charging a capacitor on A8/A9 | `rules.mk` lines 4-6; `voyager.c` lines 308-321; RMK `boot.rs` lines 19-30 |
| Right half unplugged | `is_transport_connected()`, documented for a "gaming mode" layer | `readme.md` lines 28-39; `matrix.c` line 229 |
| USB | `3297:1977`, 4 HID interfaces (section 2.2) | `keyboard.json` lines 8-11 |

**Consequence for dynamic keymaps (INFERRED):** the keymap, EEPROM, RGB state and the raw-HID endpoint all live in one MCU. Nothing has to be synchronised to the other half, and the board is flashed once. That makes a VIA/Vial Voyager simpler than a VIA/Vial Corne.

### 9.3 The Corne as the open-source reference point

| Aspect | Corne (crkbd) | Voyager |
|---|---|---|
| Hardware license | Open: MIT (`LICENSE_MIT`, © 2023 foostan) and CC BY 4.0 (`LICENSE_CC`); PCB, plate and case files in `pcbs/`, `plates/`, `cases/` (`foostan/crkbd@63366fb`) | not published |
| Keys | 3×6 + 3 per half = 42 (`LAYOUT_split_3x6_3`; also 3×5+3) | 4×6 + 2 per half = 52 |
| Controllers | **one MCU per half**: Pro Micro (ATmega32U4) on rev1, RP2040 on rev4.x (`qmk/qmk_firmware@7a1bbf3` `keyboards/crkbd/rev1/keyboard.json` line 94 `"development_board": "promicro"`; `rev4_1/info.json` lines 10-11) | one MCU + I/O expander |
| Half-to-half link | split serial: rev1 soft serial on D2; rev4.1 RP2040 PIO ("vendor") serial; `split.transport.sync.matrix_state` (`rev1/keyboard.json` lines 18-27; `rev4_1/info.json` lines 44-78) | I2C to the MCP23018 |
| Flashing | **each half separately** ("Once the firmware has been written to one side, follow the same procedure for the other side"); UF2 drag-and-drop on RP2040 (`foostan/crkbd` `docs/firmware/rev4/firmware_en.md` lines 28-37) | once, via DFU |
| USB IDs | VID 0x4653; PID 0x0001 (rev1), 0x0004 (v4) (`crkbd/info.json` line 6; `rev4_1/standard/keyboard.json` line 4) | 0x3297:0x1977 |
| Dynamic keymap in mainline QMK | `rev4_1/info.json` lines 23-25: `"dynamic_keymap": {"layer_count": 6}` | none |
| VIA | official: `the-via/keyboards@9e3e9f4` `v3/crkbd/crkbd.json`; `the-via/qmk_userspace_via@3e440ab` `keyboards/crkbd/keymaps/via/rules.mk` (`VIA_ENABLE = yes`) | none official |
| Vial | `vial-kb/vial-qmk@dd43959` `keyboards/crkbd/keymaps/vial` (`VIA_ENABLE`/`VIAL_ENABLE`, RGBLIGHT, 4 layers, unlock combo (0,0)+(0,1); `rules.mk` lines 1-17, `config.h` lines 21-26). Maintained since at least 2023-06; last touched 2025-06-29. | one keymap, one commit (2025-04-11) |
| Maker's remap story | the maker ships VIA and Vial `.uf2` builds for every v4 PCB and tells users to remap in VIA (load a JSON via the Design tab) or Vial (`firmware_en.md` lines 5-60) | Oryx (cloud build + reflash) |
| ZMK / wireless | yes (ZMK shields `corne_left`/`corne_right`; ZMK Studio live remap) | no port found |

**What carries over to this app (INFERRED):**
1. **Protocol drivers over one transport.** A Corne running VIA or Vial uses the same 0xFF60/0x61 32-byte transport as the Voyager's Oryx firmware. If the Swift HID layer separates transport (IOHIDManager or CoreHID, 32-byte reports) from protocol (Oryx, VIA, Vial), Corne support later is "add a driver and a geometry", not a rewrite. Detection: section 7.5.
2. **Split-keyboard caveat when the app talks VIA to a Corne.** QMK split keyboards process keycodes on the USB-connected half. A VIA-written keymap therefore lives in that half's EEPROM, and plugging USB into the other half can show a different keymap. This is INFERRED from QMK's split design and is not verified in this study. It does not affect the Voyager (single MCU).
3. **Geometry source.** For Corne-class boards, the VIA/Vial definition (`layouts.keymap` KLE with `"row,col"` labels, section 7.3) or Vial's compressed `vial.json` (fetched from the board) is the geometry. For the Voyager, Oryx's metadata is richer.
4. **ZMK Studio is a different protocol family.** ZMK's live-remap UI talks protobuf RPC over a **USB CDC-ACM serial port** or a **custom BLE GATT service**, not raw HID (`zmkfirmware/zmk@4dd95d7` `docs/docs/development/studio-rpc-protocol.md` lines 13, 129-137). It needs a `&studio_unlock` binding and a `studio-rpc-usb-uart` build snippet (`docs/docs/features/studio.md` lines 45, 78-104). This is only relevant if the app later targets wireless ZMK boards. On macOS it would mean `/dev/cu.usbmodem*` serial I/O, not IOHID.
5. **Voyager-like open hardware exists.** `carrefinho/forager` (CERN-OHL-P-2.0, 425 stars, last push 2025-11-22) is "a Voyager-inspired 34-key low-profile wireless split keyboard powered by ZMK" (README lines 1-12). It shows that the Voyager form factor is reproducible in open hardware, but it runs ZMK, not QMK.

### 9.4 Open-source host software to learn from

Activity is from the GitHub API on 2026-10-11. "Read, don't copy" marks GPL code that cannot be pasted into a closed-source or MIT app.

| Project | Language / UI | License | Protocol | Boards | Activity | What to take from it |
|---|---|---|---|---|---|---|
| `bogo/probe` | Swift, AppKit, IOHIDManager | MIT | Oryx (pair + key/layer events). It also decodes a custom 32-byte "KH" telemetry format from user-modified firmware with keycode, mods, layer mask and tap count (`TelemetryCodec.swift` lines 44-76). | Voyager | 2026-04-30 → 2026-05-03 | The closest Swift reference for stock firmware (section 8.1). The "KH" format shows what richer telemetry would need: firmware changes. |
| `vibewrks/zsa-overlay` | Swift/AppKit UI + Rust hidapi sidecar | MIT | Oryx v5 events | Moonlander | 2026-10-09 | Session robustness: version request with 400 ms timeout × 2, drain stale reports before pairing, 700 ms pairing timeout, `E00002C5` → "busy", 1 s presence re-check, 0.5-4 s reconnect backoff (`Sidecar/src/hid.rs` lines 12-27, 114-161, 290-296, 364-372) |
| `martinezooo/keyjitsu` | Rust, egui; CLI + TUI | MIT (links `zapp-core`: MIT + Commons Clause) | Oryx + local QMK builds + zapp flashing | Voyager (macOS-tested) | created 2026-08-11, last commit 2026-10-08, 26 stars | The closest product analogue to the planned app: live view, key editor with tap/hold/double/tap-hold, local build and flash, per-key RGB, heatmap, autolayer, layer minimap (README lines 47-100). It extends the serial with a local state id to reconcile app state against the board (lines 144-160). |
| `angusjfw/hbz` (agent-deck) | Rust + egui | none stated | Oryx: LED painting, events, `SET_LAYER` | Voyager | 2026-10-07 | Hardware-verified notes: TCC, exclusivity, brightness, reconnect (spec lines 191-214) |
| `monorkin/voyager-disco` | Rust CLI | MIT | Oryx RGB | ZSA boards | 2026-07-25 | Pitfall: strict `== 0x04` protocol check (section 3.5) |
| `Enriquefft/oryx-bench`, `pmaxhogan/starview`, `eshaan-mehta/zsa-typer-tui`, `fk1blow/voyager-base-layers` | Rust / shell | MIT | Oryx | ZSA boards | 2026 | More examples (found by GitHub code search for `0x1977 0xff60` / `PAIRING_INIT 0x3297`; not reviewed in depth) |
| `FireBall1725/LayerLens` | Swift (SwiftUI/AppKit) | **GPL-3.0** (read, don't copy) | VIA raw HID, plus its own firmware module for layer events | QMK/Vial boards | 2026-08-21 | Swift VIA client; layout lookup from `the-via/keyboards` by VID:PID |
| `hello-malek/micromap` | Swift (Xcode app + SPM kit) | README says MIT; GitHub reports NOASSERTION | VIA | Work Louder Creator Micro | 2026-07-20 | Sandboxed raw-HID app (section 8.3). Its README notes that stock VIA "does not expose … the controller's current active layer" or "per-LED frame streaming", so those need firmware extensions. |
| `travjunt/keyframe` | Swift | MIT | VIA, with read-back after every write | Creator Micro | 2026-07-25 | Write-then-verify discipline and backup/restore; no Accessibility or Input Monitoring |
| `srwi/keypeek` | Rust, egui | **GPL-3.0** (read, don't copy) | VIA/Vial/ZMK layer overlay | many | 2026-10-08, 200 stars | Overlay UX (LayerLens is its Swift rewrite) |
| `vial-kb/vial-gui` | Python/Qt | **GPL-2.0** (read, don't copy) | VIA + Vial (complete) | Vial boards | 2026-05-25, 1,430 stars | Reference implementation of every Vial command, the unlock flow and VialRGB |
| `the-via/app` | TypeScript, WebHID | **GPL-3.0** (read, don't copy) | VIA | VIA boards | 2026-09-22, 1,631 stars | Definition handling, keycode catalog |
| `zsa/kontroll` | Rust | MIT | Keymapp gRPC | ZSA | 2025-02-22 | Keymapp API client (section 5.2) |

### 9.5 Implementation lessons distilled from these projects

1. Query `FE` first and accept a version range. Gate features (automouse needs >= 0x05). Never require equality (`voyager-disco` `device.rs` lines 22, 108-112).
2. Drain queued input reports before sending `01`. Reports from an earlier session can still be queued (`zsa-overlay` `hid.rs` lines 363-372, "they describe an older pairing").
3. After `01`, wait for `05 <layer> FE` with a timeout. zsa-overlay uses 700 ms. Ignore bytes after `FE` (section 3.1).
4. Expect no held-key snapshot on attach (section 3.5).
5. Map `kIOReturnExclusiveAccess` (0xE00002C5) to a "Keymapp (or another tool) is connected" state, not to an error. Re-check enumeration about once a second so a silent unplug is noticed (`zsa-overlay` `hid.rs` lines 193-206).
6. Host colours are scaled by global brightness and kept only in RAM. Send `05 00` on quit and on sleep (section 3.7).
7. With hidapi on macOS, writes need a leading 0x00 report-ID byte (33 bytes). With `IOHIDDeviceSetReport(…, reportID 0, 32 bytes)` they do not.
8. Swift pattern gotcha seen in `bogo/probe` `TelemetryCodec.swift` lines 89-90: in `case 6, 7 where bytes[3] == 0xFE:` the `where` clause binds only to the last pattern (`7`). Swift's grammar is `case-item-list → pattern where-clause? | pattern where-clause? , case-item-list` (The Swift Programming Language, "Statements → Switch Statement" grammar). Write `case 6 where …, 7 where …:` or test the stop byte separately.
9. Treat key events as sensitive. Keep them in memory only and say so in the privacy text (section 3.8).

---

## 10. Open questions / unverified

1. **Keymapp exclusive open:** inferred from linked symbols and now observed by third parties with hidapi clients (section 5.4). Still to verify with a `kIOHIDOptionsTypeNone` client on hardware:
   - (a) with Keymapp connected, `IOHIDDeviceOpen` on interface #1 returns 0xE00002C5;
   - (b) when Keymapp connects *after* your app, your client is seized and later un-seized;
   - (c) `ioreg -l` shows `ClientSeized` on the HID user client (IOHIDLibUserClient debug dict key, line 1085).
2. **Keymapp API `sustain` field** semantics, and the exact Oryx command each RPC emits. Keymapp is closed source.
3. **Which MCU variant the user's Voyager has** (STM32, bootloader `3297:0791`; or GD32, `3297:1791`), and what differs between Oryx's standard and `?alt=true` builds. Both matter before any self-built "flash once" firmware. Check the variant by read-only USB enumeration while the board is in bootloader mode.
4. Whether Oryx web's stored-pairing path (`sendPacket(2, …)`) hangs on fw22+ firmware, or whether ZSA clears it elsewhere. This does not matter for a native app, which should always send `01`.
5. `EVT_TOGGLE_SMART_LAYER` / `EVT_TRIGGER_SMART_LAYER` (0x09/0x0A) have no firmware caller in fw25 + modules@13890cd. They may be wired to keycodes in future firmware.
6. Behaviour of CoreHID `monitorNotifications` for devices without report IDs (`id: nil`) is not tested, and no surveyed project uses CoreHID.
7. The live device was not attached, so no `hidutil`/`ioreg` capture of the real interface properties exists. Re-run `hidutil list | grep 0x3297` with the board plugged in.
8. What the closed **Navigator companion app** (macOS) talks to: the digitizer interface, raw HID, or something else. If it uses the raw-HID interface with hidapi defaults, it would also seize it (INFERRED risk).
9. The split-keyboard VIA caveat in section 9.3 item 2 is unverified. It only matters if Corne/VIA support is added.

---

## 11. Requests made

- **Revision 1 (to ZSA properties, read-only, about 13):**
  - GET source zip (zipUrl, 1).
  - GET `configure.zsa.io/voyager/layouts/KlgM7/40xJ7M/0` HTML (1) and `/assets/index-xhNfd6BI.js` (1).
  - GET `configure.zsa.io/keymapp-startup-data.json` (2).
  - HEAD `keymapp-latest.dmg` (1).
  - WebFetch of `zsa.io/flash`, `zsa.io/keymapp`, `blog.zsa.io/{introducing-kontroll,keymapp,2206-live-flashing,2206-bye-oryx-key}`, `the-ergo-archive.zsa.io/newsletters/2022/06.html` (7).
  - No GraphQL calls, no logins, no mutations.
- **Revision 2:** **no requests to ZSA.** It used the GitHub REST API and `raw.githubusercontent.com` only:
  - repo metadata, commit pins, code and repo searches;
  - shallow clones of `bogo/probe`, `vibewrks/zsa-overlay`, `jpds/rmk-zsa-voyager` and `zsa/USBDeviceSwift`;
  - single-file fetches from QMK, VIA, Vial, foostan, RMK, ZMK and the Swift/Rust client repos;
  - about 70 requests in total.
- Downloaded content was read only, never built or executed. Python ran only as `python3 -I` with scripts kept outside the download dirs.
- Nothing was sent to the keyboard (it was not attached). Keymapp was inspected on disk only, never launched.

---

## Independent verification

Checked 2026-10-11 by an independent fact-checker. I fetched every source again myself, at the pinned commits, into `scratchpad/downloads/factcheck-03/`. The only exceptions are the Oryx web bundle and the user's source zip, which I re-read from the author's copies; the firmware's md5 matches the GraphQL `md5` returned at the time. Python ran only as `python3 -I`, with scripts in `scratchpad/scripts-factcheck03/`.

Requests to ZSA: 6, all read-only. They were 3 GETs of `oryx.zsa.io/firmware/40xJ7M` (plain, `?alt=true`, `?collate=true`), 1 GraphQL query (`revision { md5 altMd5 qmkVersion model }`), and 2 page fetches (`zsa.io/training`, `zsa.io/privacy`). Nothing was sent to the keyboard, and Keymapp was read on disk only.

### Results

| # | Claim (short) | Verdict | Evidence (re-derived) |
|---|---|---|---|
| 1 | Oryx protocol 0x05. Commands 0x00-0x0C and 0xFE; events 0x00-0x0C, 0xFE and 0xFF; stop byte 0xFE. `01` sets paired with no challenge. `SET_RGB_LED` index is unchecked. | **confirmed** (one count error, see C1) | `zsa/qmk_modules@13890cd` `oryx/oryx.h` 27-28 (`ORYX_PROTOCOL_VERSION 0x05`, `ORYX_STOP_BIT -2`), 30-45, 47-63, 65-73; `oryx.c` 144-148 (`pairing_success_event()` falls through to `PAIRING_VALIDATE: break`), 180 (`webhid_leds[param[0]] = ...`, no bound). Submodule pin: `zsa/qmk_firmware@firmware25` (`93b2b9e`) `modules/zsa` = `13890cd…` (GitHub contents API). |
| 2 | `GET_FW_VERSION` reply is `00` + ASCII serial + `FE` (NUL overwritten) | **confirmed** | `oryx.c` 121-128: `memcpy(event+1, SERIAL_NUMBER, sizeof)` then `memcpy(event+sizeof, stop, 1)`. User `config.h`: `#define SERIAL_NUMBER "KlgM7/40xJ7M"`. |
| 3 | Only `SET_LAYER` and key/layer events depend on `paired`. `03` DISCONNECT is unhandled, so it returns `FF FF`. | **confirmed** | `oryx.c` 150-160 (only `paired` check among commands), 313-314 default `oryx_error(0xFF)`, 318-332, 334-355 |
| 4 | Voyager has two MCU variants, Ignition PIDs `3297:0791` (STM32) and `3297:1791` (GD32) | **confirmed** | `zsa/zapp@a1be758` `zapp-core/src/device/ids.rs` 37-40, 59-60, 86-87. The Oryx web bundle has the same pair: DFU filter `b1` lists 1937 and 6033, and `_isIgnitionGD32()` is `productId==6033` (character offset ~885,700). |
| 5 | "Oryx serves the alternate-MCU build with `?alt=true`" (for the Voyager) | **refuted** | (a) `GET /firmware/40xJ7M?alt=true` returns **HTTP 404**, and so does `?collate=true`. (b) GraphQL `altMd5` is `null` for this revision. (c) zapp uses `FirmwareVariant::Alternate` only when `is_moonlander_revb(pid)`, which is `pid == 0x1972` (`zapp/src/main.rs` 135-139; `ids.rs` 112-113). Its doc comment says "e.g. Moonlander rev B" (`zapp-oryx/src/lib.rs` 176-177). (d) Oryx web's `requiresAltFirmware` is true only for DFU device `3297:2003` (Moonlander Ignition, ~883,602). See correction C2. |
| 6 | The user's `.bin` has one DFU suffix, `3297:0791`, at 0x100FC | **confirmed** | My parse: a single `UFD\x10` at 0x10104, so the suffix starts at 0x100FC. bcdDevice 0xFFFF, PID 0x0791, VID 0x3297, bcdDFU 0x0100, CRC 0x2e4f09fd (recomputed, matches). File md5 `4d59bb3d…` equals `revision.md5` in `layout.json`, and `build.log` builds only one `.bin`. **But see O3:** the served file has since been rebuilt. |
| 7 | USB descriptors: device `3297:1977`; 4 interfaces; raw HID = IF#1, EP 0x82 IN / 0x03 OUT, 32 B, 1 ms; report descriptor `06 60 FF 09 61 A1 01 … C0` at 0xF382 | **confirmed** | My own parse of the `.bin`: device descriptor at 0xF370, configuration at 0xF2FC (116 B, 4 IF, 500 mA), and the report-descriptor bytes are identical. Minor: bmAttributes is 0xA0, so remote-wakeup is also set. |
| 8 | MCP23018 scans the right half over I2C from the single (left) MCU; 2 × IS31FL3731; matrix 12×7 | **confirmed** | fw25 `keyboards/zsa/voyager/config.h` 7-8, 12-13; `matrix.c` 13-17, 40-57, 104-105 ("right side is scanned by reading the mcp23018 registers"), 199-204 (right rows → 6-11); `keyboard.json` 47 (`"driver": "is31fl3731"`), 50 (`max_brightness` 175); `readme.md` 3 ("active left side") |
| 9 | Oryx key index = kNN label = RGB LED index; the report's `jC[row][col]` table | **confirmed, wording caveat** | I computed the table from the fw25 `keyboard.json` `rgb_matrix.layout`, and it equals the report's table exactly. Cross-check against `layout.json`: idx 0 = `=`/Esc, idx 6 = Tab, idx 24 = Enter/MO(1), idx 26 = `6`, idx 44 = `N`, idx 51 = Space/MO(2). **Caveat:** this is the number in the `kNN` label, not the position in the `LAYOUT` array. The `LAYOUT` array (lines 162-215) interleaves rows: its position 6 is `k26` at matrix [6,0]. An implementer who uses array order gets the wrong keys. |
| 10 | Keymapp seizes; a hidapi open fails with "exclusive access" while Keymapp is connected; Keymapp reconnects after the other client closes | **confirmed** (as observations) | `angusjfw/hbz@65531cd` spec 207-212, verbatim. `vibewrks/zsa-overlay@2892e2d` `Sidecar/src/hid.rs` 26-27 (`"E00002C5"`), 289-296. hidapi seizes by default: `libusb/hidapi@852cc68` `mac/hid.c` 476 and 1538-1541; `sstallion/go-hid@3879eca` `hid_darwin.c` 473. Keymapp 1.3.7 binary: 0 occurrences of `SetOpenExclusive` and 0 of `_Cfunc_hid_darwin_set_open_exclusive`, while other go-hid symbols are present. The author's caveat still stands: all observers are seizing clients. |
| 11 | IOKit: an open fails while another client has seized the device; a new seizer forces existing clients out | **confirmed, wording nuance** | `IOHIDFamily-2238.100.59` (tag → commit `777ccd96…`). `IOHIDDevice.cpp` 1217-1220 (`accept=false` if `_seizedClient`), 1228-1230 (new seizer → `kIOMessageServiceIsRequestingClose`). `IOHIDLibUserClient.cpp` 717-723 (`kIOReturnExclusiveAccess`), 864-869 (existing client is marked `fClientSeized=true; setValid(false)`, **not closed**), 872-878 (un-seized on `kIOMessageServiceWasClosed`), 1888 and 1995 (get/setReport fail "Client is seized"). |
| 12 | Raw vendor interface needs no Input Monitoring. TCC applies only to devices conforming to GD Keyboard, GD Mouse or Digitizer TouchPad. | **confirmed** (source level) | `IOHIDDevice.cpp` 527-531; `IOHIDLib/IOHIDDeviceClass.m` 511-535 (`IOHIDRequestAccess` only if the property is YES, else `_tccGranted = true`). Field quotes check out: hbz spec 191-193 "no TCC prompt"; zsa-overlay README 46. |
| 13 | Chrome opens HID with `kIOHIDOptionsTypeNone` | **confirmed** | Chromium `main` `services/device/hid/hid_service_mac.cc` line 175, fetched 2026-10-11 |
| 14 | Sandbox: `device.usb` or `device.hid` allows `IOHIDLibUserClient`; only `device.usb` allows the USB user clients | **confirmed** | local `/System/Library/Sandbox/Profiles/application.sb` lines 115-123 |
| 15 | CoreHID has `.deviceSeized`/`.deviceUnseized`, `HIDDeviceError.exclusiveAccess`, `seizeDevice()` and `dispatchSetReportRequest(type:id:data:)` | **confirmed** | SDK `CoreHID.swiftmodule/arm64e-apple-macos.swiftinterface` lines 3499, 3569, 3573-3574, 3585 |
| 16 | Corne maker ships VIA and Vial firmware for v4 and says to remap in VIA or Vial; each half is flashed separately | **confirmed** | `foostan/crkbd@63366fb` `docs/firmware/rev4/firmware_en.md` 5-26 (VIA/Vial `.uf2` links), 37 ("follow the same procedure for the other side"), 42-58. Mainline `qmk/qmk_firmware@7a1bbf3` `crkbd/info.json` 6 (VID 0x4653), `rev1/keyboard.json` 4 (0x0001), `rev4_1/standard/keyboard.json` 4 (0x0004), `rev4_1/info.json` 10 (RP2040), 23-24 (`layer_count 6`). |
| 17 | RMK Voyager port: live keymap via Vial, USB `4C4B:4643`, lighting "none", serial `rmk:<version>` | **partially correct** | README 12, `vial.json` 3-5 and RMK `DeviceConfig` defaults (vid 0x4c4b, pid 0x4643) are confirmed. **Wrong:** the serial. The port depends on crates.io `rmk 0.9.0` with `features = ["vial", …]` (`Cargo.toml` 9), and `rmk-v0.9.0` `rmk/src/config/device.rs` 16-26 sets the serial to **`vial:f64c2b3c;rmk:0.9.0`** when `vial` is on. Also, the port pins rmk 0.9.0, not RMK `main@ac1339f`; the defaults happen to be the same. |
| 18 | VialRGB direct fast-set is `07 42 <first LE16> <n≤9> (H S V)×n`; mode 1 = `VIALRGB_EFFECT_DIRECT` | **confirmed** | `vial-kb/vial-qmk@dd43959` `quantum/vialrgb.h` 7-22; `vialrgb.c` 90-110 (LE16 first index, `num_leds*3 > length` guard gives n ≤ 9, V clamped), 161-182; `vialrgb_effects.inc` 4-6. Routing: vial-qmk `quantum/via.c` 310-370. Vial keyboard id: `vial.h` 25 (`0x00000006`), `vial.c` 94-106 (byte 12 = VialRGB flag). Serial: `builddefs/build_vial.mk` 15. |
| 19 | ZSA: on-keyboard code is open source, Oryx server side is not; Keymapp API is off by default | **confirmed** | zsa.io/training: "The code that runs on the keyboard is open-source … The server-side component is a part of Oryx, which is not open-source." zsa.io/privacy: "only when you explicitly enable this API feature in Keymapp's settings (it is off by default)"; "Kontroll and Zapp are open source". |
| 20 | Keymapp API: gRPC `KeyboardService`, 12 RPCs, no streaming, over a UDS at `~/Library/Application Support/.keymapp/keymapp.sock` | **confirmed** (line-number nit) | `zsa/kontroll@be6a3c6` `proto/keymapp.proto` 94-118 (12 `rpc`, 0 `stream`); `src/api.rs` 89-104 (`KEYMAPP_SOCKET`, then `config_dir()/.keymapp/keymapp.sock`, then the App Store container path), 115 (`http://[::]:50051`). The README quote is on lines **23-25**, not 22-24. |
| 21 | Oryx web: `sendReport(0, 32 B)` then sleep 1000 ms; HID filter usage 0x61 / page 0xFF60; Voyager PID 6519 | **confirmed** | bundle `index-xhNfd6BI.js` ~869,465 (`device.sendReport(0,…),yield wi(1e3)`), ~771,581 (`MC()`), `RC=[6519]` |
| 22 | Firmware IN send timeout 100 ms; raw IN/OUT queues 4 deep; `raw_hid_task` drains all OUT reports | **confirmed** | fw25 `tmk_core/protocol/chibios/usb_main.c` 458-460, 593-598; `usb_endpoints.h` 8-9, 38-43 |
| 23 | Flash window 0x08002000 + (128k - 0x2000); RAM 32k + 8k CCM; wear-leveling 2048 B backing, 1024 B logical; `bootloader_jump` charges A8/A9 for 500 ms | **confirmed** | fw25 `ld/voyager.ld` 22, 30, 34; `wear_leveling_efl_config.h` 48-56; `voyager.c` 308-321; user `build.log` 55, 61-62 (wear-leveling EEPROM compiled). VIA 0x000C: fw25 `quantum/via.h` 42. Upstream `via.c` has no `id_bootloader_jump` case and defines a strong `raw_hid_receive` at 282. |

### Corrections

- **C1 (section 0, item 2).** "13 command codes and 13 event codes" is wrong. There are **14 commands** (0x00-0x0C plus 0xFE) and **15 events** (0x00-0x0C plus 0xFE and 0xFF), per `oryx.h` 30-63. The tables in 3.3 and 3.4 are correct.
- **C2 (sections 6, 7.6 "Which variant…", 7.7 step 6).** `?alt=true` is **not** how Oryx serves GD32 Voyagers.
  - For this revision it returns 404, and `altMd5` is `null`.
  - zapp and Oryx web use `?alt=true` only for Moonlander rev B.
  - For the Voyager, Oryx web uses a "double compilation" path. The flasher is created with `_doubleCompilation = (geometry=="voyager" && qmkVersion!="24.0")` (bundle ~886,989). `_extractIgnitionFirmare` (~882,957-883,600) then searches for the first DFU suffix with an STM32-Ignition PID (`g1=[0x0791,0x2000..0x2003]`).
    - On a 0x0791 device it flashes the bytes **before** that suffix.
    - On a 0x1791 device it flashes the bytes **after** it, which must end in a second suffix with PID 0x1791 (`zj=[6033]`). This matches zapp's `IgnitionDual` format (`firmware/mod.rs` 14-19, 87).
  - The user's fw25 file has **only** the 0x0791 image (`build.log` builds one `.bin`). By code reading, Oryx web would fail on a GD32 board with "DFU file suffix invalid." (INFERRED).
  - zapp, in contrast, would flash this single 0x0791-suffixed image onto a 0x1791 device. `validate_firmware_compatibility` only rejects STM32-DFU vs Ignition mismatches for single images (`zapp-core/src/flash/mod.rs` 46-136).
  - **How a GD32 Voyager is meant to receive fw25 firmware is therefore unresolved.** "Produce both images (as Oryx does)" is not supported for fw25. Do not ship any flashing code until the bootloader PID and the image format have been checked on real hardware.
- **C3 (sections 7.2 and 7.5).** The RMK Voyager port's USB serial is `vial:f64c2b3c;rmk:<version>`, not `rmk:<version>`. A serial-prefix test for `vial:` therefore classifies RMK as Vial, which fits its protocol. Use the VID:PID `4C4B:4643` or the manufacturer "RMK" to tell it apart from vial-qmk.
- **C4 (section 3.6).** Say "the number in the `kNN` label (equivalently, the `rgb_matrix.layout` order)", not "label order". The `LAYOUT` array order in the same file is different, and it is the argument order of the generated `keymap.c` `LAYOUT(...)`.
- **C5 (minor).**
  - The configuration's bmAttributes is 0xA0 (bus-powered + remote wakeup).
  - The `.bin` payload before the suffix is 0x100FC = 65,788 B (`build.log` reports ELF text 65,786 B, plus 2 bytes of padding).
  - IOKit does not *close* clients when a seizer arrives. It marks them seized and invalid until the seizer closes (row 11).

### Important omissions

- **O1. A second Voyager runtime PID.** zapp's `identify_keyboard` and `target_name_for_pid` treat **`0x1977 | 0x1978`** as Voyager (`ids.rs` 106, 128). Oryx web lists only 0x1977. The report recommends matching "strictly" on 0x1977, which could miss a board that enumerates as 0x1978. What 0x1978 means is unknown. Match both, and confirm with usage page 0xFF60/0x61 plus the serial format.
- **O2. Layer-event dedupe can drop a change (INFERRED from `oryx.c` 15, 55-63, 73-80, 334-355).**
  - `pairing_success_event()` sends a fresh `05 <layer> FE` but does **not** update the global `current_layer`.
  - `layer_state_set_oryx` updates `current_layer` only while paired, and suppresses an event when the new layer equals it.
  - So if a host first pairs while a non-zero layer is held, the return to layer 0 (`current_layer` still 0 from boot) is **never reported**.
  - The same happens after `paired` is cleared by a failed send and layers change before re-pairing.
  - Cheap resync: re-send `01`. It always emits a freshly computed `05`.
- **O3. The firmware for a revision can be rebuilt.** Between the author's download (md5 `4d59bb3d…`) and mine about 45 minutes later, `revision.md5` and the served `/firmware/40xJ7M` changed to `4f0376c0…`. The size is the same, the image still has a single 0x0791 suffix, and only 2 code/data bytes plus the CRC differ (0x4B84 and 0xEE5C: 0x1E→0x09). The cause is unknown; it may be a compile triggered by the concurrently driven browser session. The app should read `md5` at download time, verify the file against it, and not cache firmware by revision ID alone.
- **O4. Vial speaks an older VIA protocol.** vial-qmk reports `VIA_PROTOCOL_VERSION 0x0009`, and its 0x07/0x08/0x09 are `id_lighting_set/get/save` **without a channel byte** (vial-qmk `quantum/via.h` 42, 61-66). The table in 7.3 describes upstream 0x000C, which has `<channel> <value_id>`. A shared VIA/Vial driver must branch on the reported version.
- **O5. MCU-variant evidence conflicts.** The RMK port says the board "ships with a GD32F303CB" (README 5; GD32-specific warm-boot code in `src/main.rs` 96-113), yet its flash command targets `3297:0791` (README 55), which zapp calls "Ignition STM32". Mapping the PID to the silicon therefore rests only on zapp's naming. Treat "0791 = STM32, 1791 = GD32" as ZSA's label, not a verified hardware fact.
- **O6. Pairing never ends.** No command clears `paired` (`03` is unhandled, see row 3). After any host has paired, every keystroke produces a raw-HID IN report until reboot, even after the app quits. The report notes "no way to un-pair". Its consequence for the privacy text and for latency (the 100 ms blocking send if nobody drains the endpoint) should be stated next to the recommendation in section 0.
