# 02 - From layout to firmware to flash: generated QMK source, ZSA's QMK fork, local builds, the Voyager bootloader and DFU flashing

Study date: 2026-10-11. Project: Sextant, a native macOS (Swift/SwiftUI) replacement for Oryx.
Target: the user's ZSA Voyager, layout `KlgM7`, revision `40xJ7M`, geometry `voyager`, `qmkVersion` "25.0".
Audience: the engineer who implements build and flash in Sextant.
Conventions:
- Every technical claim cites a primary source: repo@commit + path + lines, a URL, or a local artifact path.
- **INFERRED** marks conclusions drawn from code or data rather than stated by a source.
- Paths starting `scratchpad/` are under `scratchpad/`.
- Live HID, the Oryx raw-HID protocol and Keymapp are covered in `study/03-live-hid-and-ecosystem.md`. This report links to it and does not repeat it.

---

## 0. Summary

1. **Pipeline.**
   - Oryx stores the layout as JSON (GraphQL `revision.layers[].keys`, `revision.config`, `combos`, `navigators`).
   - ZSA's server turns it into four QMK source files: `keymap.c`, `config.h`, `rules.mk` and `keymap.json`. The generator is closed source.
   - The server then builds those files with `qmk compile` against `zsa/qmk_firmware`, branch `firmware25`, using arm-none-eabi-gcc 12.2.1 (Debian package `15:12.2.rel1-1`) inside a container rooted at `/qmk` (section 3).
   - The results are published at `https://oryx.zsa.io/firmware/{revisionHashId}` (.bin) and `https://oryx.zsa.io/source/{revisionHashId}` (.zip).
   - `revision.md5` equals the md5 of the downloaded `.bin`. I verified this on 5 layouts.
2. **The firmware file** is a raw Cortex-M4 image linked at **0x08002000**, followed by a standard 16-byte **DFU suffix**.
   - The suffix fields are VID `0x3297`, PID `0x0791`, bcdDevice `0xFFFF` and bcdDFU `0x0100`, and the CRC verifies.
   - The suffix PID is the **bootloader** PID, not the keyboard PID.
   - The file has no other header or metadata. The user's file is 65,804 bytes, of which 65,788 are payload (section 5).
3. **Bootloader.** The Voyager uses ZSA's closed-source **"Ignition"** bootloader, which occupies the first 8 KiB of flash.
   - It enumerates as **`3297:0791`** on STM32 boards or **`3297:1791`** on GD32 boards.
   - It speaks **DFU 1.1 with ST DfuSe commands**: `0x21` set address, `0x41` erase page, and data written with `DNLOAD wValue=2`.
   - It uses interface 0, alt 0, 2048-byte erase pages and 2048-byte transfers.
   - In normal mode the keyboard is `3297:1977` (section 8).
4. **Entering the bootloader takes a physical action or a key.** The options are:
   - the reset button on the top edge of the left half, above the "3" key (a button, not a pinhole; zsa.io/go);
   - the `QK_BOOT` key, which the user has on layer 2 at key index 31;
   - Bootmagic: hold the top-left key while plugging in. This also wipes EEPROM.
   The stock firmware exposes no DFU runtime interface and no raw-HID "jump to bootloader" command.
5. **Tools.**
   - **Wally and wally-cli cannot flash a Voyager.** They know only `0483:DF11` (STM32 ROM DFU) and HalfKay, are deprecated, and wally-cli is archived.
   - The Voyager is flashed by Keymapp (closed), Oryx in Chrome (WebUSB), **zapp** (ZSA's open-source Rust CLI, April 2026), and `dfu-util -d 3297:0791 -a 0 -s 0x08002000:leave` (the command in QMK's `rules.mk`).
   - Two complete open reference implementations of the Voyager flash algorithm exist: Oryx's WebUSB class and zapp's `dfu.rs`.
6. **Brick risk is low.** All ZSA flashers erase only from 0x08002000 upward, so the bootloader is never touched, and the reset button always reaches the bootloader (INFERRED from `voyager.c` and the flasher code).
   Sextant must still hard-block:
   - any erase or write below 0x08002000;
   - mass erase;
   - images whose suffix PID does not match the connected bootloader;
   - STM32 images on a GD32 bootloader.
7. **Local builds are feasible but nothing is installed.**
   - Missing locally: `qmk`, `arm-none-eabi-gcc`, `dfu-util`.
   - `make` is Apple's GNU Make 3.81, and QMK needs GNU make 4.x for parallel builds.
   - OrbStack is installed but stopped. `libusb` 1.0.30 is installed through Homebrew.
   - A Voyager build needs the fork, three submodules (`lib/chibios` about 370 MB, `lib/printf`, `modules/zsa`), the `qmk` Python CLI, GNU make, an arm-none-eabi toolchain, and `dfu-suffix`.
8. **Recommendation.**
   - Flash with a **native Swift DFU implementation over IOUSBHost/IOKit**: about 300 lines, no third-party code, modeled on zapp and Oryx web.
   - Build through a pluggable backend. The **default local backend should be a pinned Debian-bookworm container image** run through Apple's Containerization framework (macOS 26+, Apple silicon; the user is on macOS 27, arm64). That reproduces ZSA's exact compiler.
   - Use QMK's prebuilt macOS toolchain (gcc 15.2) as the fallback.
   - Ship as a Developer ID, notarized, hardened-runtime app. Defer the App Sandbox until an on-device test confirms that IOUSBHost user clients pass the `com.apple.security.device.usb` sandbox rule (section 10).
9. **Open-source status (the user asked about this).**
   - The Voyager's **firmware** is open source under GPL-2.0, both in ZSA's fork and in upstream QMK (`keyboards/zsa/voyager`). ZSA's flashing CLI and its QMK modules are also open.
   - The **hardware** design (schematics, PCB) is not published. No ZSA repo contains it.
   - The Corne is fully open hardware (`foostan/crkbd`, CC-BY-4.0 + MIT). Its ecosystem (QMK Configurator/API, VIA/Vial, ZMK, keymap-drawer) shows what transfers to the Voyager and what does not (section 11).

---

## 1. Sources examined (pinned)

| Source | Version / commit | Local copy (under `scratchpad/downloads/`) |
|---|---|---|
| User's source zip (zipUrl) | built 2026-09-16 05:08 UTC, 51,796 B, md5 `6daee83b...` | `layout-source/source.zip`, `layout-source/unzipped/` (identical copy in `layout-source-c/`) |
| User's .bin (hexUrl) | 65,804 B, md5 `4d59bb3dba601672ecefd27e2641561c` | `layout-bin/firmware.bin`. The same bytes came from `https://oryx.zsa.io/firmware/40xJ7M` (`oryx-firmware-endpoint/`) |
| Four other public Voyager layouts (fw 25.0) with generated sources | JRGQm/7vbZQA, e5Rrr/zLP4rM, m9dpx/ga0MZq, XlrR4/Xbx94o | `oryx-source-JRGQm/`, `oryx-sources-examples/{e5Rrr,m9dpx,XlrR4}/` (I downloaded the last three for this report). JSON in `scratchpad/oryx/examples/` |
| `zsa/qmk_firmware` | branch **`firmware25`** (default branch) @ `93b2b9ec3368f86c5eb5a2e3f934049f8daef885` (2026-09-02) | `zsa-qmk/qmk_firmware` (sparse, blob:none), `zsa-qmk_firmware-fw25/repo` |
| `zsa/qmk_modules` (submodule `modules/zsa`) | `13890cd7856175de20798689d15ba6a46bf0c5c7` | `zsa-qmk_modules/repo` |
| `qmk/qmk_firmware` upstream | master @ `7a1bbf37c5c07da4ea0a162bb139083a46ef40a1` | `qmk-voyager-kbjson/` (Voyager files), crkbd via raw.githubusercontent |
| `zsa/zapp` | `a1be75837323001ad1ae8e5787d88cd33f2ccc46` (v1.0.2, 2026-07-09) | `zapp/zapp` |
| `zsa/wally` | `dba608a2c08e66d41c5530444e9097eab5ede627` (2024-08-21); wiki `7e5e7f6b...` (2026-05-19) | `wally/wally`, `wally/wiki` |
| `zsa/wally-cli` | `2d0da1ee4c4e7fa5407c5b6653b0d908cbfe9044` (archived) | `wally-cli/wally-cli` |
| dfu-util | `f9a537c93935d9d536b5ea29b54a226160b2b111` (2025-03-02) | `dfu-util/dfu-util` |
| `poulainpi/oryx-with-custom-qmk` | `26bfbe6fbb4059554743575e177124ad2488a311` | `oryx-with-custom-qmk/repo` |
| Oryx web bundle | `configure.zsa.io/assets/index-xhNfd6BI.js`, md5 `34fbb4d676e5dd056e2acf1999f26dae` (the hash changes per deploy) | `oryx-frontend/index-xhNfd6BI.js`, `oryx-web/assets/` |
| QMK installer / toolchains | `install.qmk.fm` script; `qmk/qmk_toolchains` release `v15.2.0-1`; `qmk/qmk_flashutils` `20260711` | `qmk-install-script/`; GitHub API |
| Apple SDK | `MacOSX27.0.sdk` (Xcode 27.0), `/System/Library/Sandbox/Profiles/application.sb` (Darwin 27.0.0) | local |

---

## 2. Pipeline at a glance

```
Oryx JSON (GraphQL revision)                                       [ZSA server, closed]
  layers[].keys[52], config{}, combos[], navigators{}  --generator-->  keymap.c / config.h / rules.mk / keymap.json
                                                                        |
             zsa/qmk_firmware@firmware25 + modules/zsa + lib/chibios  <-+  qmk compile (gmake -j8, gcc 12.2.1, /qmk)
                                                                        |
                         .elf -> objcopy -O binary -> .bin -> dfu-suffix -v 3297 -p 0791 -a
                                                                        |
            oryx.zsa.io/firmware/{rev} (.bin)    oryx.zsa.io/source/{rev} (.zip: sources + build.log + .bin + .md5 + README)
                                                                        |
     Flasher (Oryx WebUSB | Keymapp | zapp | dfu-util)  --DfuSe over USB EP0-->  Ignition bootloader 3297:0791 @ 0x08002000
```

Sources:
- Build command: `build.log` line 1.
- Compiler: `build.log` line 5.
- `/qmk/modules/...` paths: `build.log` lines 24, 26.
- DFU suffix rule: `builddefs/common_rules.mk` lines 249-258.
- Suffix arguments: `keyboards/zsa/voyager/rules.mk` line 6.
- Endpoints:
  - Oryx bundle `get hexUrl()` / `get zipUrl()` at byte offset 794,790: `Ah+"firmware/"+hashId` and `Ah+"source/"+hashId`.
  - `zapp-oryx/src/lib.rs` lines 192-199.
  - `poulainpi` workflow `.github/workflows/fetch-and-build-layout.yml` line 54.

The GraphQL `hexUrl`/`zipUrl` fields are signed Rails ActiveStorage redirects to `oryx.nyc3.digitaloceanspaces.com` (`layout-bin/headers.txt`). `/firmware/{rev}` serves the same bytes directly (`oryx-firmware-endpoint/headers.txt`, md5 match).

How Oryx triggers a server build, for reference only (this study did not call it): the mutation `compileRevision(hashId)` returns `md5 altMd5 qmkVersion qmkUptodate buildErrorLog buildSource buildConfig buildRules` (Oryx bundle offset 637,966).

---

## 3. The generated source zip, file by file

Archive listing of `layout-source/source.zip`:

| File | Bytes | Content and role |
|---|---|---|
| `README.md` | 2,585 | Generic instructions. Build against ZSA's fork or mainline QMK; copy `*_source/` into `qmk_firmware/keyboards/zsa/voyager/keymaps/<name>/`; `qmk compile -kb zsa/voyager -km <name>`; `qmk flash` and press reset. Links the layout URL. |
| `build.log` | 22,642 | ZSA's server build output, ANSI-coloured. Line 1 is the exact make command (below). Line 5 is the compiler. Lines 10-21 are generated headers. Lines 22-192 compile about 160 units. Lines 196-198 are the size. |
| `zsa_voyager_KlgM7.bin` | 65,804 | The firmware, byte-identical to hexUrl. |
| `zsa_voyager_KlgM7.bin.md5` | 33 | `4d59bb3dba601672ecefd27e2641561c` plus a newline. Equals `revision.md5`. |
| `zsa_voyager_my-macos-layout-fork_source/keymap.c` | 8,236 | Keymap, custom keycodes, LED map and `process_record_user` (section 4). |
| `.../config.h` | 133 | 4 lines (below) |
| `.../rules.mk` | 209 | 8 lines (below) |
| `.../keymap.json` | 104 | `{"modules": ["zsa/oryx", "zsa/navigator_trackpad", "zsa/defaults"]}`. This is the QMK community-module list. |
| (optional) `.../i18n.h` | - | Present only when an international layout is selected. Examples: JRGQm (`#define KC_PC_UNDO LCTL(KC_Z)`), XlrR4 (`UK_*`, `US_*` defines). |

The folder is named `<geometry>_<slugified layout title>_source`, and the `.bin` inside the zip is `zsa_voyager_<layoutHashId>.bin`.

Exact server command (`build.log` line 1):

```
gmake --jobs=8 --output-sync=target -r -R -f builddefs/build_keyboard.mk -s KEYBOARD=zsa/voyager KEYMAP=KlgM7 KEYBOARD_FILESAFE=zsa_voyager TARGET=zsa_voyager_KlgM7 VERBOSE=false COLOR=true SILENT=false QMK_BIN="qmk" BUILD_DIR=.build/KlgM7
```

This is the argument list that `qmk compile` builds in `lib/python/qmk/build_targets.py` lines 106-142 (`zsa/qmk_firmware@93b2b9e`), plus a custom `BUILD_DIR`. ZSA therefore runs `qmk compile -j 8` with the keymap folder named after the layout hashId.

The user's `config.h`, in full:

```c
#define USB_SUSPEND_WAKEUP_DELAY 0
#define SERIAL_NUMBER "KlgM7/40xJ7M"
#define LAYER_STATE_8BIT

#define RGB_MATRIX_STARTUP_SPD 60
```

The user's `rules.mk`, in full:

```make
CONSOLE_ENABLE = no
COMMAND_ENABLE = no
MOUSEKEY_ENABLE = no
ORYX_ENABLE = yes
RGB_MATRIX_CUSTOM_KB = yes
SPACE_CADET_ENABLE = no
PRECISION_TRACKPAD_ENABLE = yes
PRECISION_TRACKPAD_DRIVER = navigator_trackpad
```

`build.log` "Size after" reports 65,786 data bytes. That figure comes from `arm-none-eabi-size --target=ihex` on the `.hex` (`common_rules.mk` line 202). The `.bin` payload is 65,788 bytes. The 2-byte difference is a gap filled by `objcopy -O binary` (INFERRED: section alignment). m9dpx and e5Rrr show the same +2, and XlrR4 shows +0.

---

## 4. How Oryx JSON maps to generated C and config

The mapping below comes from 5 Oryx JSON + generated-source pairs: the user's layout, JRGQm, e5Rrr, m9dpx and XlrR4, all firmware 25.0. The generator is not public. This section is an empirical spec for Sextant's own generator.

### 4.1 Key order: Oryx index vs. `LAYOUT()` argument order

- `layers[n].keys` has 52 entries in **Oryx index order**:
  - 0-23: left half, 4 rows of 6;
  - 24-25: left thumbs;
  - 26-49: right half, 4 rows of 6;
  - 50-51: right thumbs.
- Verified on the user's layout: `keys[6] = KC_TAB`, `keys[31] = QK_BOOT` on layer 2, and `keys[24]` is the `LT(1,KC_ENTER)` thumb key. This also matches `study/03` section 3.6 and the `kNN` labels in `keyboards/zsa/voyager/keyboard.json` lines 163-214.
- `LAYOUT_voyager(...)` (alias of `LAYOUT`, `keyboard.json` lines 157-159) takes its arguments **row-interleaved**:
  `[0..5, 26..31, 6..11, 32..37, 12..17, 38..43, 18..23, 44..49, 24, 25, 50, 51]`.
  Source: the order of `layouts.LAYOUT.layout` entries, `keyboard.json` lines 163-214.
- The generator emits the keymap in this interleaved order. Example: row 1 of the user's layer 0 is `DUAL_FUNC_0, KC_1..KC_5, KC_6..KC_0, KC_MINUS` (`keymap.c` line 21).
- The **RGB LED index equals the Oryx index**, so `ledmap[layer][i]` uses Oryx order with no reordering.
- Combos refer to Oryx indices (`combos[].keyIndices`).

### 4.2 Key JSON schema (as observed)

```json
{ "tap":       {"code": "KC_Z", "layer": null, "macro": null, "modifiers": {"leftAlt":..,"leftGui":..,"leftCtrl":..,"rightAlt":..,"rightGui":..,"leftShift":..,"rightCtrl":..,"rightShift":..}, "color": null, "description": null, "modifier": null},
  "hold":      { same shape } | null,
  "doubleTap": { same shape } | null,
  "tapHold":   { same shape } | null,
  "tappingTerm": null | <signed delta ms>,
  "glowColor": null | "#RRGGBB",
  "customLabel": null | "text", "icon": null, "emoji": null, "about": null, "aboutPosition": null, "lockGlowColor": null,
  "swapped": false, "detached": false, "pristine": true, "swapping": false, "history": [] }
```

`modifiers` key order in the JSON is an artifact of storage: shorter keys first, as Postgres `jsonb` orders them (INFERRED). It does not encode nesting order.

### 4.3 Per-key action to C

| Oryx JSON shape | Generated C | Evidence |
|---|---|---|
| `tap.code` only | the keycode verbatim, e.g. `KC_Q` | user `keymap.c` lines 21-39 |
| `tap.code` + `tap.modifiers` | nested modifier macros: `RGUI(KC_LBRC)`, `LGUI(LSFT(KC_LBRC))`, `LALT(LGUI(KC_K))`, `LGUI(LCTL(LSFT(KC_B)))`. Nesting order varies between samples but is **functionally irrelevant**: the 16-bit `QK_MODS` value is the same. | user line 38; JRGQm lines 202, 531 |
| tap = basic keycode, hold = **single modifier** keycode | **Mod-tap** `MT(MOD_LALT, KC_Z)`, `MT(MOD_RSFT, KC_QUOTE)`, `MT(MOD_RALT, KC_SLASH)` | user lines 23-24; JSON `keys[19]` tap `KC_Z`, hold `KC_LEFT_ALT` |
| tap = basic keycode, hold = `{"code":"MO","layer":N}` | **Layer-tap** `LT(N, KC_ENTER)` | user line 25; JSON `keys[24]` |
| tap + hold where `MT`/`LT` cannot express it (hold is a non-modifier like `KC_ESCAPE`, or tap carries modifiers like `LSFT(KC_S)`) | **"Dual function"**: `#define DUAL_FUNC_n LT(<l>, <kc>)` as a unique placeholder keycode, plus a `process_record_user` case that tests `record->tap.count > 0` and calls `register_code16/unregister_code16` of the tap or hold code, then `return false`. The placeholder `LT(l,kc)` pairs look arbitrary, e.g. user `LT(15, KC_1)`, JRGQm `LT(1, KC_U)`, `LT(8, KC_E)`. They only need to be unique and in the LT range so QMK runs its tap/hold engine. Layer holds in dual functions become `layer_on(n)`/`layer_off(n)`. | user lines 17, 130-144; JRGQm lines 94-140, 1180-1260, 1655-1690 |
| `doubleTap` and/or `tapHold` present | **Tap dance** `TD(DANCE_n)`, `TAP_DANCE_ENABLE = yes` (see 4.4) | JRGQm `keys[0]` and lines 81-92, 424-824 |
| `tap.macro = {keys:[{code,delay,modifiers}], applyAlt, endEnter, name}` | custom keycode `ST_MACRO_n` (enum from `ZSA_SAFE_RANGE`), case `ST_MACRO_n: if (pressed) SEND_STRING(...)` (see 4.5) | JRGQm layer 2 key 32 -> `ST_MACRO_0`, lines 845-848 |
| `tap.code = "RGB"` with `tap.color = "#ff0000"` | custom keycode `HSV_<h>_<s>_<v>` with handler `rgblight_mode(1); rgblight_sethsv(h,s,v);` | user lines 10-12, 150-167 |
| `RGB_SLD` | custom keycode, handler `rgblight_mode(1)` | user lines 9, 145-149 |
| ZSA keycodes `TOGGLE_LAYER_COLOR`, `LED_LEVEL` | emitted verbatim. Defined by module `zsa/defaults` as `QK_KB`, `QK_KB+1` (`zsa/qmk_modules@13890cd` `defaults/defaults.h` lines 7-11); handled in `keyboards/zsa/voyager/voyager.c` lines 233-279 | user line 35 |
| QMK keycodes (`QK_BOOT`, `CW_TOGG`, `DM_PLY1`, `QK_LLCK`, `OSM(MOD_LSFT)`, `KC_MS_*`, `QK_DYNAMIC_TAPPING_TERM_UP`, `KC_MS_JIGGLER_TOGGLE`) | verbatim. Some switch on features or modules (4.7). | JRGQm lines 146-209 |
| `KC_TRANSPARENT` | `KC_TRANSPARENT` (not `_______`) | user lines 30-39 |
| `customLabel`, `description`, `icon`, `emoji`, `about*` | **ignored**: no trace in any generated file | user `keys[44]` `customLabel:"Back"` -> plain `RGUI(KC_LBRC)` |
| `tappingTerm` (per key, signed delta) | inside `get_tapping_term()`: `case <keycode>: return g_tapping_term -75;`, plus `#define TAPPING_TERM_PER_KEY` | XlrR4 `keymap.c` lines 71-78, `config.h` |
| `glowColor` | an entry in `ledmap` for that layer and index (4.6) | JRGQm |

Always emitted, whatever the layout contains (user lines 1-6, 47-57, 111-128):
- `#include QMK_KEYBOARD_H`, `#include "version.h"`, `#define MOON_LED_LEVEL LED_LEVEL`;
- the `ZSA_SAFE_RANGE` fallback;
- `hsv_to_rgb_with_value()`, which scales the ledmap colour by the current RGB matrix brightness;
- `keyboard_post_init_user(){ rgb_matrix_enable(); }`;
- a `QK_MODS ... QK_MODS_MAX` case that applies modifiers separately for consumer and mouse keycodes, with `wait_ms(2)`.

### 4.4 Tap dance code shape

This is the generated code for JRGQm `keys[0]`: tap `KC_ESCAPE`, hold `{"code":"TO","layer":11}`, tapHold `{"code":"TO","layer":10}` (JRGQm `keymap.c` lines 424-489):

- A shared `dance_step()` classifies each press as `SINGLE_TAP`, `SINGLE_HOLD`, `DOUBLE_TAP`, `DOUBLE_HOLD`, `DOUBLE_SINGLE_TAP` or `MORE_TAPS`.
- JSON `tap` maps to `SINGLE_TAP`, `hold` to `SINGLE_HOLD`, `doubleTap` to `DOUBLE_TAP`, and **`tapHold` to `DOUBLE_HOLD`** ("tap, then hold").
- `on_dance_n` handles extra taps: count==3 taps the tap code three times, and count>3 taps it once per extra tap.
- `dance_n_finished` calls `register_code16` for keycodes, `layer_move(n)` for `TO`, and `layer_on(n)` for `MO`.
- `DOUBLE_SINGLE_TAP` emits `tap_code16(tap); register_code16(tap)`.
- `dance_n_reset` starts with `wait_ms(10)`, then unregisters or calls `layer_off`.
- The actions table is `tap_dance_actions[] = { [DANCE_n] = ACTION_TAP_DANCE_FN_ADVANCED(on_dance_n, dance_n_finished, dance_n_reset) }` (lines 814-825).
- The `dancesTapAction` and `legacyDualFunctionDances` config flags probably alter this template (INFERRED; not observed).

### 4.5 Macros

JSON `macro.keys[i] = {code, delay, modifiers}` becomes:
- `SS_<mods>(SS_TAP(X_<code without KC_>))` for each key;
- `SS_DELAY(<delay>)` between consecutive keys (none after the last key);
- concatenated into one `SEND_STRING(...)`.

`applyAlt: true` wraps the whole sequence in `SS_LALT(...)`, which is the Windows Alt-code entry: JRGQm `SEND_STRING(SS_LALT(SS_TAP(X_KP_0)SS_DELAY(100) SS_TAP(X_KP_1)...))`, line 912. `endEnter` presumably appends `SS_TAP(X_ENTER)` (INFERRED; not observed).

Example (JRGQm `ST_MACRO_0`, line 847, from JSON layer 2 key 32):
```c
SEND_STRING(SS_LCTL(SS_LGUI(SS_TAP(X_1)))SS_DELAY(100)  SS_LCTL(SS_LGUI(SS_TAP(X_2)))SS_DELAY(100)  SS_LCTL(SS_LSFT(SS_TAP(X_O))));
```

### 4.6 RGB: per-key and per-layer LED maps

- `ledmap[layer][52][3]` holds HSV tuples. Only layers with colours get an entry.
- A key's `glowColor` takes precedence. Otherwise the layer `color` fills every LED, as in the user's layer 1 `#00F0FF` -> 52 x `{131,255,255}` (user `keymap.c` lines 59-64).
- Keys with no colour are `{0,0,0}`. `set_layer_color()` turns those LEDs **off** (lines 66-80).
- `rgb_matrix_indicators_user()` (lines 82-106):
  - returns early while a host owns RGB (`rawhid_state.rgb_control`, the Oryx protocol; `study/03` section 3.7);
  - honours `keyboard_config.disable_layer_led`;
  - switches on `biton32(layer_state)`, the highest active layer.
- The `case` list covers layers 1..max coloured layer. JRGQm has cases 1-10 while its 12th layer has none (INFERRED rule). Layer 0 is never in the list, so the configured RGB effect runs there.
- `capsLockStatus` adds code that paints LEDs red on layer 0 while Caps Lock is on (JRGQm lines 307-312, 412-419).

**Colour conversion.** JSON `#RRGGBB` becomes QMK HSV (0-255 each):
- `v = round(V*255)` is exact.
- `s` is within ±1 of `round(S*255)`.
- `h` is within **±2** of `round(hue_degrees*256/360)`.

This was measured over 39 distinct chromatic colours and 383 LED cells (script `scratchpad/scripts/s02/ledpairs.py`). Oryx's exact rounding is not reproducible from the hex (INFERRED: the UI may keep a higher-precision HSV). Sextant can use its own deterministic conversion: a 1-2 step hue error is invisible on the LEDs.

### 4.7 Config and features to `config.h` / `rules.mk` / `keymap.json`

Observed across the five layouts. The settings catalog with defaults is in `study/04-oryx-settings-catalog.json`, which lists 100 keys.

| Oryx input | Output | Evidence |
|---|---|---|
| always | `config.h`: `USB_SUSPEND_WAKEUP_DELAY 0` (setting `wakeupDelay`, default 0), `SERIAL_NUMBER "<layoutHashId>/<revisionHashId>"`, `RGB_MATRIX_STARTUP_SPD 60` | all 5 |
| always | `rules.mk`: `CONSOLE_ENABLE = no`, `COMMAND_ENABLE = no`, `ORYX_ENABLE = yes`, `RGB_MATRIX_CUSTOM_KB = yes`, `SPACE_CADET_ENABLE = no` | all 5 |
| always | `keymap.json` modules include `zsa/oryx` and `zsa/defaults` | all 5 |
| number of layers | `LAYER_STATE_8BIT` (3 and 5 layers) or `LAYER_STATE_16BIT` (8 and 12 layers). Rule probably ">= 8 layers -> 16BIT" (INFERRED). | user, e5Rrr, m9dpx, JRGQm |
| no mouse keycodes used | `MOUSEKEY_ENABLE = no` (INFERRED rule: present in the 2 layouts without `KC_MS_*`, absent in the 3 with them) | user, XlrR4 vs m9dpx, JRGQm, e5Rrr |
| `tappingTerm: 165` | `#undef TAPPING_TERM` / `#define TAPPING_TERM 165` | m9dpx |
| `perKeyTappingTerm: true` + key `tappingTerm` | `#define TAPPING_TERM_PER_KEY` + `get_tapping_term()` using `g_tapping_term` | XlrR4 |
| `QK_DYNAMIC_TAPPING_TERM_*` keys used | `DYNAMIC_TAPPING_TERM_ENABLE = yes` | XlrR4, JRGQm |
| `permissiveHold: true` | `#define PERMISSIVE_HOLD` | XlrR4 |
| `chordalHold: true` | `#define CHORDAL_HOLD` + `const char chordal_hold_layout[...] = LAYOUT('L'x6,'R'x6, ... ,'*','*','*','*')` (thumbs `'*'`) | XlrR4, JRGQm lines 230-236 |
| `flowTap: 100` | `#define FLOW_TAP_TERM 100` | JRGQm |
| `oneShotTimeout: 2000` | `#undef ONESHOT_TIMEOUT` / `#define ONESHOT_TIMEOUT 2000` | JRGQm |
| `rgbTimeout: N` (minutes) | `#undef RGB_MATRIX_TIMEOUT` / `#define RGB_MATRIX_TIMEOUT N*60000` (2 -> 120000, 3 -> 180000) | JRGQm, e5Rrr |
| `disabledAnimations: [...]` | one `#undef ENABLE_RGB_MATRIX_<EFFECT>` per item | JRGQm lines 28-72, XlrR4 |
| `autoshift: true`, `autoshiftTimeout: 150` | `AUTO_SHIFT_ENABLE = yes`; `#define AUTO_SHIFT_TIMEOUT 150` | e5Rrr |
| `comboTerm: 40`, n combos | `COMBO_ENABLE = yes`; `#define COMBO_TERM 40`; `#define COMBO_COUNT n`; `const uint16_t PROGMEM comboK[] = { <keycodes at keyIndices on layerIdx>, COMBO_END};` and `combo_t key_combos[COMBO_COUNT] = { COMBO(comboK, <trigger keycode>) }`. Combos are **keycode-based**, so they fire on any layer where those keycodes appear. | JRGQm lines 238-304, m9dpx lines 78-84 |
| `mouseDelay: 8`, `mouseInterval: 14` | `#undef/#define MOUSEKEY_DELAY 8`, `MOUSEKEY_INTERVAL 14` | JRGQm |
| `capsLockStatus: true` | `#define CAPS_LOCK_STATUS` + `led_update_user` + indicator code | JRGQm |
| international layout (`uk`, ...) | `i18n.h` with `UK_*` etc. | XlrR4 |
| `DM_*` keys | `DYNAMIC_MACRO_ENABLE = yes` | JRGQm |
| `CW_TOGG` | `CAPS_WORD_ENABLE = yes` | JRGQm, XlrR4 |
| `QK_LLCK` | `LAYER_LOCK_ENABLE = yes` | JRGQm |
| (unclear trigger) | `REPEAT_KEY_ENABLE = yes` (JRGQm has no `QK_REP` key) | JRGQm |
| `navigators.right.kind = "trackpad"` | `PRECISION_TRACKPAD_ENABLE = yes`, `PRECISION_TRACKPAD_DRIVER = navigator_trackpad`, module `zsa/navigator_trackpad` | user (`layout-full.json` navigators), m9dpx, JRGQm |
| trackpad + automouse | module `zsa/automouse`, `POINTING_DEVICE_DRIVER = custom`, `AUTOMOUSE_LAYER/TIMEOUT/THRESHOLD` | JRGQm |
| `navigators.left.kind = "trackball"`, `sensitivity 25`, `automouseTime 650`, `invertScrollX/Y` | `POINTING_DEVICE_ENABLE = yes`, `POINTING_DEVICE_DRIVER = navigator_trackball`, `NAVIGATOR_TRACKBALL_CPI 25`, `NAVIGATOR_SCROLL_DIVIDER 75`, `POINTING_DEVICE_AUTO_MOUSE_ENABLE`, `AUTO_MOUSE_TIME 650`, `NAVIGATOR_SCROLL_INVERT_X/Y`, and others | e5Rrr |
| `KC_MS_JIGGLER_TOGGLE` used | module `zsa/mousejiggler` | JRGQm |
| `qmkCanary: true` | no visible output. Probably selects the newest firmware branch (INFERRED). | user, default layout |

### 4.8 Implications for Sextant's generator

- Generate the same four files. Reuse ZSA's boilerplate verbatim, so the Oryx live protocol, Keymapp and zapp `update` keep working. That requires the `zsa/oryx` module, `ORYX_ENABLE`, and `SERIAL_NUMBER "layout/revision"`.
- If Sextant stops round-tripping through Oryx, choose a `SERIAL_NUMBER` convention. Oryx web, Keymapp and zapp read the serial to fetch the layout from Oryx (`study/03` section 3.4; `zapp/src/main.rs` lines 102-117). A value that is not an Oryx ID makes those tools report "not an Oryx firmware" rather than misbehave (INFERRED).
- `MT` and `LT` need the tap to be a basic keycode (`QK_BASIC`) and the hold to be one modifier or `MO`. Use the DUAL_FUNC pattern otherwise, which is exactly what Oryx does.
- A golden test: feed the five JSON/source pairs (paths in section 1) through Sextant's generator and diff. Normalise whitespace and DUAL_FUNC placeholder numbering.

---

## 5. The compiled `.bin`, byte level

Inspected with `python3 -I scratchpad/scripts/s02/binscan.py` (read-only parse; nothing executed).

| Offset | Bytes / value | Meaning |
|---|---|---|
| 0x0000 | `00 04 00 20` = 0x20000400 | Initial MSP. Top of a 1 KiB ChibiOS main stack at the start of RAM (`ram0` org 0x20000000, `ld/voyager.ld` line 30). |
| 0x0004 | `bd 22 00 08` = 0x080022BD | Reset vector, Thumb, inside the app window starting 0x08002000. **This is the evidence that the image is linked at 0x08002000.** |
| 0x0008-0x019F | 104 vectors in total (16 system + 88 IRQ slots) | 85 slots point to the default handler 0x080022BF. Non-default: SVCall 0x0800EA79; IRQs 11-17 (DMA1 ch1-7), 28 (TIM2, ChibiOS ST), 31/32 (I2C1 EV/ER), 56-60 (DMA2 ch1-5), **75 (USB_LP with the STM32F303 remap)**. These match the STM32F303 IRQ map. |
| 0x01A0 | `72 b6 ...` (`cpsid i`) | Code (ChibiOS `crt0_v7m.S` reset handler) |
| 0xEA14 | ASCII `KlgM7/40xJ7M` | `SERIAL_NUMBER`, returned by Oryx `GET_FW_VERSION` (`study/03` section 3.4) |
| 0xF2A2 / 0xF2BE / 0xF2D0 | UTF-16LE `KlgM7/40xJ7M`, `Voyager`, `ZSA Technology Labs` | USB string descriptors. Device and config descriptors are at 0xF370 / 0xF2FC, parsed in `study/03` section 2.2. |
| 0x100FC-0x1010B | `ff ff 91 07 97 32 00 01 55 46 44 10 fd 09 4f 2e` | **DFU suffix** (DFU 1.1 appendix B, little endian): bcdDevice 0xFFFF, idProduct **0x0791**, idVendor **0x3297**, bcdDFU 0x0100, `"UFD"`, bLength 16, dwCRC 0x2E4F09FD |

- The CRC is the standard DFU suffix CRC: CRC-32 (reflected, poly 0xEDB88320), init 0xFFFFFFFF, **no final XOR**. In other words `~zlib.crc32(file[:-4])`, which I computed and which matches. Reference: dfu-util `src/dfu_file.c` lines 271-301 (verify) and 373-447 (write).
- The suffix comes from `dfu-suffix -v 3297 -p 0791 -a <bin>` (`rules.mk` line 6; `common_rules.mk` lines 254-256). bcdDevice defaults to 0xFFFF.
- There is no other header, version block, signature or checksum. The QMK version and build date are not embedded as strings.
- The firmware occupies 0x08002000-0x080120FB: 53.5% of the 120 KiB link window.
- Every other Voyager build I downloaded (4 layouts) has exactly one suffix, `3297:0791`, at end-16. None is a dual STM32+GD32 image.

---

## 6. ZSA's QMK fork and the Voyager definition

### 6.1 Repository, branch, submodules

- **Repo:** `https://github.com/zsa/qmk_firmware`. It is a fork of `qmk/qmk_firmware`, GPL-2.0, "forked for ZSA's Oryx Configurator (to safeguard stability)" (GitHub API).
- **Firmware v25 = branch `firmware25`**, which is also the default branch. Head at study time: `93b2b9ec3368f86c5eb5a2e3f934049f8daef885` (2026-09-02, "fix: system sleep key not working on Windows").
- The fork uses no version tags. Its branches are `firmware17` ... `firmware25`. The `poulainpi` workflow derives the branch as `firmware$(printf "%.0f" qmkVersion)` (workflow lines 48, 85).
- The fork is **pruned to ZSA boards**: `keyboards/` contains only `zsa/` (ergodox_ez, moonlander, planck_ez, voyager, common), and the tree has 2,490 blobs totalling 11.2 MB (`work/zsa_qmk_firmware.tree.json`).
- Submodules (`.gitmodules` lines 1-30; gitlinks at 93b2b9e):

| Path | URL | Pinned commit | Needed for a Voyager build? |
|---|---|---|---|
| `lib/chibios` | qmk/ChibiOS | `be44b3305f9a...` | **yes** (RTOS + HAL; `build.log` lines 85-184) |
| `lib/chibios-contrib` | qmk/ChibiOS-Contrib | `77cb0a4f7589...` | no. Used only if `halconf_community.h` exists (`platforms/chibios/platform.mk` lines 316-335). The Voyager has none, and `build.log` compiles no contrib file. |
| `lib/printf` | qmk/printf | `c2e3b4e10d28...` | **yes** (`build.log` line 52) |
| `modules/zsa` | zsa/qmk_modules | `13890cd78561...` | **yes** (oryx, navigator_*, defaults, ...) |
| `lib/lufa`, `lib/vusb`, `lib/pico-sdk`, `lib/googletest`, `lib/lvgl` | qmk/* | ... | no (AVR, V-USB, RP2040, tests, Quantum Painter) |

### 6.2 `keyboards/zsa/voyager` (fork @93b2b9e)

| Item | Value | Source |
|---|---|---|
| Files | `keyboard.json`, `config.h`, `rules.mk`, `post_rules.mk`, `voyager.c/.h`, `matrix.c`, `halconf.h`, `mcuconf.h`, `ld/voyager.ld`, `keymaps/{default,oryx}`, `readme.md` | directory listing |
| MCU | `"processor": "STM32F303"`. readme: "Hardware Supported: Voyager (STM32F303xC)". MCU selection: Cortex-M4F, `MCU_SERIES = STM32F3xx`, default `BOARD = GENERIC_STM32_F303XC`, which pulls in ChibiOS `ST_STM32F3_DISCOVERY/board.c`. | `keyboard.json` line 6; `readme.md` line 6; `platforms/chibios/mcu_selection.mk` lines 292-327; `platforms/chibios/boards/GENERIC_STM32_F303XC/board/board.mk`; `build.log` line 180 |
| Bootloader setting | `"bootloader": "custom"` -> `platforms/chibios/bootloaders/custom.c` (weak no-ops), overridden by `voyager.c` | `keyboard.json` line 7; `custom.c` lines 19-22; `build.log` line 84 |
| Linker | `MCU_LDSCRIPT = voyager`; `flash0 org 0x08002000 len 128k-0x2000`; `ram0 0x20000000 32k`; `ram4 0x10000000 8k` (CCM). Header comment: "STM32F303xB memory setup". | `rules.mk` line 1; `ld/voyager.ld` lines 17-38 |
| USB | VID 0x3297, PID 0x1977, device_version 0.0.1 | `keyboard.json` lines 8-15 |
| Features | bootmagic (matrix [0,1]), caps_word, deferred_exec, mousekey, extrakey, nkro, swap_hands, rgb_matrix | `keyboard.json` lines 16-28 |
| Matrix | 12 rows x 7 cols, `ROW2COL`, `CUSTOM_MATRIX = lite`. Left half is read directly: rows B10-B15, cols A0-A3, A6, A7, B0. Right half is read over I2C1 (B6/B7) through an **MCP23018** I/O expander at 0x20. | `config.h` lines 7-8; `keyboard.json` line 29; `rules.mk` line 3; `matrix.c` lines 18-27, 37-75; `voyager.h` line 12 |
| RGB | driver `is31fl3731` x2 at I2C 0x74 (GND, left, LEDs 0-25) and 0x77 (VCC, right, LEDs 26-51); max brightness 175 | `keyboard.json` lines 46-50; `config.h` lines 12-13; `drivers/led/issi/is31fl3731.h` lines 53-56; `voyager.c` lines 133-197 |
| Status LEDs | LED1 B5, LED2 B4 (left); LED3/LED4 on MCP23018 (right) | `voyager.h` lines 14-17 |
| Bootloader jump | sets A8 and A9 push-pull high, `wait_ms(500)`, sets A9 low, then `NVIC_SystemReset()`. Comment: "The ignition bootloader is checking for a high signal on A8 for 100ms when powering on the board." `mcu_reset()` drives both low and resets. A8 is configured as input and A9 output-low at boot. | `voyager.c` lines 94-99, 308-330 |
| Flash recipe | `PROGRAM_CMD = $(call EXEC_DFU)`, `DFU_ARGS = -d 3297:0791 -a 0 -s 0x08002000:leave`, `DFU_SUFFIX_ARGS = -v 3297 -p 0791` | `rules.mk` lines 4-6 |

Note on `PROGRAM_CMD`: no `EXEC_DFU` macro exists in the fork, which defines only `EXEC_DFU_UTIL` (`platforms/chibios/flash.mk` lines 13-24). `PROGRAM_CMD` therefore expands to empty, and `make zsa/voyager:<km>:flash` falls through to the STM32 branch: `$(call EXEC_DFU_UTIL)` with the `DFU_ARGS` above (`flash.mk` lines 96-113). The end result is correct (INFERRED from make semantics).

### 6.3 ZSA modules used by Oryx builds (`zsa/qmk_modules@13890cd`)

| Module | Role |
|---|---|
| `oryx` | raw-HID live protocol. `qmk_module.json`: `raw: true, via: false`. See `study/03`. |
| `defaults` | ZSA keycodes `TOGGLE_LAYER_COLOR=QK_KB`, `LED_LEVEL`, `ZSA_SAFE_RANGE`; keycode aliases across firmware versions; default `SERIAL_NUMBER "default/latest"` (`defaults/defaults.h`, `post_config.h` lines 8-10, `keycode_aliases.h`) |
| `navigator_trackpad`, `navigator_trackball`, `automouse`, `mousejiggler`, `doubleclick`, `keycolors` | accessories and extra features |

### 6.4 Upstream QMK vs. the fork

Upstream QMK master (`7a1bbf3`) has `keyboards/zsa/voyager` with:
- identical `rules.mk` (`qmk-voyager-kbjson/upstream_rules.mk` lines 1-10);
- an essentially identical `keyboard.json`: the fork adds only `"tapping": {"toggle": 1}`;
- a `voyager.c` without the Oryx-module hooks.

So **mainline QMK can build Voyager firmware**, but without ZSA's community modules. Those modules are needed by every Oryx-generated `keymap.json` and for Keymapp and Oryx live features. The keyboard is also in the QMK API keyboard database (`https://keyboards.qmk.fm/v1/keyboards/zsa/voyager/info.json`: STM32F303, bootloader custom).

---

## 7. Building locally on macOS

### 7.1 What a Voyager build needs

| Requirement | Why / where | Notes |
|---|---|---|
| `zsa/qmk_firmware@firmware25` checkout | sources | about 11 MB of files (pruned fork) |
| `lib/chibios` (+ `lib/printf`, `modules/zsa`) | RTOS, HAL, modules | ChibiOS at the pinned commit is **368.5 MB, 5,372 files**, of which 306 MB is vendor CMSIS headers under `os/common/ext` (`work/qmk_ChibiOS.tree.json`). Contrib (42.8 MB) is not needed. |
| `qmk` Python CLI (pip `qmk`) + repo `requirements.txt` (argcomplete, colorama, dotty-dict, hid, hjson, jsonschema>=4, milc>=1.9.0, pygments, pyserial, pyusb, pillow) | `build_keyboard.mk` shells out to `$(QMK_BIN)` (`qmk`) for about 14 generators: `generate-rules-mk`, `json2c`, `generate-config-h`, `generate-community-modules-*`, `generate-version-h`, ... (`builddefs/build_keyboard.mk` lines 26, 148-295, 435-445). The top-level `Makefile` aborts if `qmk hello` fails (lines 414-415). | So plain `make` still needs Python + `qmk`. `SKIP_GIT=yes` skips the submodule sync/check (`Makefile` lines 419-423). |
| GNU make | `qmk compile` uses `gmake` if present, else `make` (`lib/python/qmk/commands.py` lines 18-26). With `-j>1` it adds `--output-sync=target` (lines 40-42), which **GNU make 3.81 (macOS `/usr/bin/make`) does not support**. | Use GNU make 4.x, or build with `-j1`. |
| `arm-none-eabi-gcc` / binutils / newlib | compile, link, `objcopy -O binary` (`platforms/chibios/platform.mk` lines 487-494) | ZSA uses **12.2.1 (Debian `15:12.2.rel1-1`)** (`build.log` line 5). QMK's prebuilt macOS toolchain is **gcc 15.2.0**: `qmk_toolchains-gcc15.2.0-host_macosARM64.tar.zst`, 139.1 MB (GitHub release `v15.2.0-1`). |
| `dfu-suffix` (ships with dfu-util) | appends the suffix (`common_rules.mk` lines 254-256). If it is missing, the `if` statement returns 127 and the `.bin` recipe fails (INFERRED). | Or pass `DFU_SUFFIX_ARGS=` and append the 16-byte suffix in Swift (section 5 gives the format). |
| git | clone and submodules | `/opt/homebrew/bin/git` present |

Outputs are written to `.build/` and copied to the repo root as `zsa_voyager_<km>.bin` (`common_rules.mk` lines 183-185, 258).

### 7.2 What this Mac has now (checked read-only)

| Tool | State |
|---|---|
| `qmk`, `arm-none-eabi-gcc`, `arm-none-eabi-objcopy`, `dfu-util`, `dfu-suffix`, `gmake`, `avr-gcc` | **not found** |
| `make` | `/usr/bin/make`, GNU Make **3.81** |
| `python3` | `/usr/bin/python3` 3.9.6 (CLT) |
| Homebrew matches (`qmk\|arm\|dfu\|libusb\|gcc\|make\|hidapi`) | `automake`, `cmake`, `libusb` (**1.0.30**, LGPL-2.1+), `linearmouse` |
| Containers | `docker` -> OrbStack 2.2.3 CLI; daemon **not running**. No `podman`, `colima` or Apple `container`. |
| Other | `rustc`/`cargo`, `go`, Xcode 27.0 / MacOSX27.0.sdk; macOS 27.0.1 arm64; 487 GiB free |

### 7.3 Minimal reproducible command sequence

This was not executed: no installs were allowed.

```sh
git clone --depth 1 -b firmware25 https://github.com/zsa/qmk_firmware qmk && cd qmk
git submodule update --init --depth 1 lib/chibios lib/printf modules/zsa
python3 -m venv .venv && . .venv/bin/activate && pip install qmk -r requirements.txt
mkdir -p keyboards/zsa/voyager/keymaps/sextant && cp <generated>/* keyboards/zsa/voyager/keymaps/sextant/
qmk config user.qmk_home="$PWD"
SKIP_GIT=yes qmk compile -j 8 -kb zsa/voyager -km sextant      # needs gmake 4.x on PATH, arm-none-eabi-* and dfu-suffix
# -> zsa_voyager_sextant.bin
```

Alternatively, keep generated keymaps outside the checkout with an External Userspace: `qmk config user.overlay_dir=...` (QMK `docs/newbs_external_userspace.md` lines 44-93).

**Disk (INFERRED from tree sizes):**
- about 0.4 GB of sources (ChibiOS dominates), plus shallow `.git` objects;
- plus about 0.5 GB for the unpacked toolchain (139 MB `.zst` covers arm, avr and riscv);
- plus about 50 MB of Python venv;
- that totals about **1 GB native**.
- The Docker image `qmkfm/qmk_cli:latest` is **821 MB compressed (arm64)** (Docker Hub API, 2026-03-28).

**Time:** not measured, because no toolchain was available. About 160 C/ASM translation units (`build.log` lines 22-192), so I expect roughly 10-40 s clean with `-j8` on Apple silicon and a few seconds incremental (INFERRED). Measure this in the first spike.

**Reproducibility check (acceptance test):** build the user's zip sources and compare to `md5 4d59bb3d...`. With gcc 12.2.1 the result may be byte-identical. With gcc 15.2 expect different bytes but the same behaviour (INFERRED).

### 7.4 How community projects build

| Project | Approach | Source |
|---|---|---|
| `poulainpi/oryx-with-custom-qmk` (ZSA has an official fork, `zsa/oryx-with-custom-qmk`) | GitHub Actions on `ubuntu-latest`. It queries Oryx GraphQL for the latest revision, downloads `oryx.zsa.io/source/{rev}`, merges the `oryx` branch into `main` (user C edits), checks out the `firmware<N>` submodule branch, builds a `debian:latest` image (`gcc-arm-none-eabi libnewlib-arm-none-eabi dfu-util`, `pip install qmk`), then runs `qmk setup zsa/qmk_firmware -b firmware<N>` and `make zsa/voyager:<id>`. The `.bin` is uploaded as an artifact. | `Dockerfile` lines 1-16; workflow lines 43-126; blog `blog.zsa.io/oryx-custom-qmk-features` (2024-11-07) |
| `j7j7/voyager-keyboard-helper` | local: installs the qmk CLI and toolchains per QMK docs, clones `zsa/qmk_firmware` `firmware25`, patches the Oryx export, builds and flashes | `gh-readmes/j7j7_voyager-keyboard-helper.README.md` |
| `Enriquefft/oryx-bench` | Docker build backend; flashing delegated to zapp | `gh-readmes/Enriquefft_oryx-bench.README.md` |
| QMK official macOS setup | `install.qmk.fm`: `uv`-managed Python venv plus prebuilt toolchains from `qmk/qmk_toolchains`, flashing utilities from `qmk/qmk_flashutils` (macOS ARM64: 3.4 MB), and Homebrew `zstd clang-format make hidapi libusb dos2unix git` | `qmk-install-script/install.qmk.fm.sh` lines 281, 506-550, 656-672 |

### 7.5 Build-backend options for Sextant

| Option | What the app does | Pros | Cons |
|---|---|---|---|
| **A. Oryx cloud** (`compileRevision` mutation) | push the layout to Oryx and let ZSA compile; download `/firmware/{rev}` | zero local toolchain; identical to Oryx | needs an Oryx account and writes to ZSA (out of scope for this read-only study); depends on ZSA; custom C is impossible |
| **B. Container (recommended local default)** | Apple **Containerization** Swift package (Apache-2.0; "Requirements: macOS 26", Apple silicon, Virtualization.framework; README on main 2026-10-11). Runs a pinned `debian:bookworm` image with `gcc-arm-none-eabi` 12.2.1, `python3-qmk`, make and dfu-util, with the fork checkout mounted. Needs entitlement `com.apple.security.virtualization` (Apple docs). | **reproduces ZSA's exact compiler**; one versioned artifact; no Homebrew/Python drift; no notarization of hundreds of toolchain Mach-Os | macOS 26+ only; pre-1.0 API (tag 0.49.0); about 0.8-1 GB image plus kernel; VM start overhead (sub-second per README) |
| **C. Native managed toolchain** | download `qmk_toolchains` (gcc 15.2) and `qmk_flashutils` into `~/Library/Application Support/Sextant/`, a `uv` Python venv with `qmk`, and a bundled or downloaded GNU make 4.x; run `qmk compile` | fastest builds; works on older macOS | many moving parts; compiler differs from ZSA's; spawning downloaded executables complicates the sandbox and Gatekeeper (INFERRED) |
| D. Remote CI (GitHub Actions, as poulainpi) | push sources to the user's repo; poll the artifact | no local tools | needs a GitHub account and token, minutes of latency |
| E. QMK API (`api.qmk.fm/v1/compile`, status "running") | POST a QMK keymap.json for `zsa/voyager` | free and hosted | builds **upstream** QMK without `zsa/*` modules, so no Oryx live protocol. QMK keymap.json cannot express DUAL_FUNC, tap-dance functions or the ledmap. Not suitable (INFERRED). |

**Recommendation:**
- Define a `BuildBackend` protocol.
- Ship **B** as the default local builder on macOS 26+, using an image pinned by digest and a fork commit pinned to `93b2b9e`.
- Keep **C** as the fallback.
- Allow **A** only behind an explicit user opt-in, if Sextant ever syncs to Oryx.
- Cache the fork plus `lib/chibios` once, about 400 MB.
- Write generated sources into a per-build directory and pass `SKIP_GIT=yes`.

---

## 8. Bootloader and flashing protocol

### 8.1 Identity

| Item | Value | Source |
|---|---|---|
| MCU (ZSA's definition) | STM32F303 (Cortex-M4F). The linker uses the 128 KiB "xB" layout; the readme says "xC". | section 6.2 |
| MCU variants seen by flashers | **STM32** (Ignition PID `0x0791`) and **GD32** (Ignition PID `0x1791`) | zapp `zapp-core/src/device/ids.rs` lines 32-43, 54-67, 82-94; Oryx bundle offset 880,081 (`g1=[1937,8192..8195]`, `zj=[6033]`) |
| Community claim | "The Voyager ships with a GD32F303CB (STM32F303CB-compatible)" (`jpds/rmk-zsa-voyager` README and `memory.x`, commit `69527d6`). That port also maps 8 KiB of CCM at 0x10000000, an STM32F303 feature, and flashes `3297:0791` (the STM32 PID). **The claim conflicts with its own setup; treat as unverified.** | `gh-readmes/jpds_rmk-zsa-voyager.README.md`; GitHub API |
| Normal mode | `3297:1977` "ZSA Technology Labs" / "Voyager" / serial `KlgM7/40xJ7M`; 4 HID interfaces, no DFU runtime interface | `keyboard.json` lines 8-15; `.bin` descriptors (`study/03` section 2.2) |
| zapp's normal-mode PIDs for Voyager | `0x1977 \| 0x1978` (meaning of 0x1978 unknown; perhaps a GD32 variant, INFERRED) | `ids.rs` lines 98-109 |
| Bootloader | **Ignition** (ZSA, closed source, no public repo; GitHub org `zsa` lists none). `3297:0791` "Voyager (Ignition STM32)", `3297:1791` "Voyager (Ignition GD32)". The Oryx bundle reads `bcdDevice` as the Ignition version ("Ignition bootloader detected, version: x.y.z"). | `ids.rs` lines 86-87; Oryx offsets 883,837 (`claim()`) and 885,391 (`getBootloaderVersion`) |
| Not used on the Voyager | STM32 ROM DFU `0483:DF11` (QMK `STM32_BOOTLOADER_ADDRESS 0x1FFFD800` for F303, `mcu_selection.mk` line 326) is not reachable through firmware: `bootloader: custom`, and there is no `bootloader_jump` to system memory (INFERRED) | `custom.c`; `voyager.c` lines 308-321 |

### 8.2 Entering the bootloader

| Method | How | Source |
|---|---|---|
| Reset button | a dedicated button (not a pinhole) on the **top edge of the left half**, "near the '3' key in the default layout" (zsa.io/go) | Oryx asset `voyager-reset-light-Blm1OVY4.png` ("Reset Button" callout); Oryx flash UI "Press the reset button, then click Connect" (`_revisionId-CtR9sUEn.js` offset 168,670) |
| `QK_BOOT` keycode | calls `bootloader_jump()`, which charges the A8 capacitor for 500 ms and resets; Ignition sees A8 high for at least 100 ms. **The user has `QK_BOOT` at layer 2, Oryx index 31** (right half, top row, outermost). | `voyager.c` lines 308-321; `layout.json` |
| Bootmagic | hold matrix [0,1] (Oryx index 0, the top-left key) while plugging in. It **resets EEPROM** (`eeconfig_disable`) and then calls `bootloader_jump()`. | `keyboard.json` lines 26-28; `quantum/bootmagic/bootmagic.c` lines 35-75 @93b2b9e; QMK `docs/features/bootmagic.md` lines 20-24 |
| Host software command | **none in stock firmware.** There is no DFU runtime descriptor, so `DFU_DETACH` is impossible. The Oryx protocol has no bootloader command (`study/03` section 3.3). VIA's `id_bootloader_jump` (0x0B) is not compiled in. | `.bin` config descriptor; `oryx.h` |
| Leaving without flashing | `DNLOAD(wValue=0, len 0)` then `GETSTATUS`. Oryx's QC page does this after reading the bootloader version. | Oryx offset 773,777 (`new $C(...); claim(); getBootloaderVersion(); _dfuReboot()`) |

A future Sextant firmware could add a raw-HID "enter bootloader" command that calls `bootloader_jump()` (INFERRED; it needs a custom build).

### 8.3 Flash memory map

| Range | Contents | Source |
|---|---|---|
| 0x08000000-0x08001FFF (8 KiB) | Ignition bootloader. **Never erase or write.** | `ld/voyager.ld` line 22 (app org 0x08002000); zapp `IGNITION_START_ADDRESS` (`dfu.rs` line 22) |
| 0x08002000-... | application image (the `.bin` payload) | same |
| 0x08002000 + 0x1E000 = 0x08020000 | end of the linker's app window (120 KiB) | `ld/voyager.ld` line 22 |
| end of **physical** flash, minus 2 KiB | QMK wear-leveling "EEPROM" (backing 2048 B, logical 1024 B), located at runtime from the flash-size register | `study/03` section 7.6 |
| ≤ 0x08042000 | upper bound the flashers accept (start + 256 KiB) | Oryx `Qj=134488064`; zapp `IGNITION_END_ADDRESS` (`dfu.rs` line 23) |

Because flashers erase only `[0x08002000, start+len+2048(+2048))`, **EEPROM survives reflashing** unless an image approaches the end of flash (INFERRED). Bootmagic, or a QMK EECONFIG magic change, resets it.

### 8.4 Firmware file format accepted by flashers

- **Single image:** `payload || suffix(VID 0x3297, PID 0x0791)`.
- **Dual image** ("double compilation"): `imgSTM32 || suffix(PID in {0x0791, 0x2000..0x2003}) || imgGD32 || suffix(PID 0x1791)`. Oryx web selects by the connected bootloader PID (`_extractIgnitionFirmare`, offset 882,824). zapp does the same (`firmware/mod.rs` lines 81-101; `flash/dfu.rs` lines 56-68).
- Oryx web enables dual-image parsing for `geometry=="voyager" && qmkVersion!="24.0"` (offset 886,804). No dual image exists in the five fw25 Voyager builds I downloaded.
- On a GD32 bootloader (`0x1791`), Oryx web would throw "DFU file suffix invalid" for these single-image files. zapp would flash the STM32 image anyway, because `validate_firmware_compatibility` checks only Ignition vs. ROM-DFU (`flash/mod.rs` lines 71-101). **Sextant must refuse** a single STM32 image on PID `0x1791` until GD32 firmware semantics are known.
- Suffix parsing:
  - Oryx: `vid=(t[5]<<8)+t[4]`, `pid=(t[3]<<8)+t[2]`, "UFD" at bytes 8-10 (`_parseDFUSuffix`, offset 882,297; `_extractSTM32DFUSuffix`, offset 882,522).
  - zapp: scans the whole file byte by byte for `UFD` at offset 8 of each 16-byte window (`dfu_bin.rs` lines 24-57).
- Firmware URL variants: `/firmware/{rev}`, `?alt=true` (alternate MCU, e.g. Moonlander rev B, PID 0x2003), and `?collate=true` (Moonlander/Halfmoon). Sources: `zapp-oryx/src/lib.rs` lines 171-199; Oryx offsets 794,790 and 885,793.
- Integrity: Oryx downloads with an expected md5 but discards the comparison (`t==Dc(s)` is evaluated and ignored, offset 885,793). **Sextant should enforce `md5(file) == revision.md5`.**

### 8.5 The protocol at byte level

Transport: USB control transfers on EP0 only. Configuration 1, interface 0, alt 0. Oryx calls `selectConfiguration(1)` and `claimInterface(0)` (`claim()`, offset 883,837; `selectConfiguration(Xj)` at 883,995). zapp calls `detach_and_claim_interface(0)` (`dfu.rs` line 95).

The protocol is **DFU 1.1 with ST DfuSe extensions** (the same command set as dfu-util's DfuSe mode). QMK drives it with `dfu-util -s 0x08002000:leave` (`rules.mk` line 5).

Setup packets (`bmRequestType bRequest wValue wIndex wLength`, little endian):

| Request | Setup bytes | Data | Notes |
|---|---|---|---|
| DFU_GETSTATUS | `A1 03 00 00 00 00 06 00` | IN 6 bytes: `bStatus, bwPollTimeout[3] (LE24), bState, iString` | dfu-util `dfu.h` line 64; parse `pollTimeout = LE32(bytes 1..4) & 0xFFFFFF` (Oryx `_getStatus`, offset 881,086) |
| DFU_CLRSTATUS | `21 04 00 00 00 00 00 00` | - | send when `bState == 10` (dfuERROR) |
| DFU_GETSTATE | `A1 05 00 00 00 00 01 00` | IN 1 byte | optional |
| DfuSe SET_ADDRESS | `21 01 00 00 00 00 05 00` | `21 a0 a1 a2 a3` | address pointer for the next `wValue=2` block (dfu-util `dfuse.c` lines 216-221) |
| DfuSe ERASE_PAGE | `21 01 00 00 00 00 05 00` | `41 a0 a1 a2 a3` | erases the 2 KiB page containing the address (`dfuse.c` lines 199-215) |
| DfuSe MASS_ERASE | `21 01 00 00 00 00 01 00` | `41` | **never send to Ignition.** Wally sent it to ROM DFU (`wally/dfu.go` line 197). Ignition's behaviour is unknown. |
| Data block | `21 01 02 00 00 00 LL LL` | up to 2048 bytes | `wValue=2` means "write at the address pointer + (2-2)*size" |
| Leave / manifest | `21 01 02 00 00 00 00 00` (zapp, dfu-util) or `21 01 00 00 00 00 00 00` (Oryx) | none | followed by GETSTATUS; the device may drop off the bus |

DFU states (dfu-util `usb_dfu.h` lines 90-100):

| Value | State |
|---|---|
| 2 | dfuIDLE |
| 3 | DNLOAD-SYNC |
| 4 | **DNBUSY** |
| 5 | **DNLOAD-IDLE** |
| 7 | MANIFEST |
| 10 | **ERROR** |

**Reference algorithm.** This is the union of Oryx web `$C.flash()` (offsets 880,240-885,700) and zapp `flash_dfu()` (`dfu.rs` lines 50-172):

1. Wait for a device with VID `0x3297` and PID in {`0x0791`, `0x1791`}. zapp waits 500 ms after hotplug (`watcher.rs` lines 98-105).
2. Open it, use configuration 1, claim interface 0.
3. GETSTATUS. If `bState == 10`, CLRSTATUS and GETSTATUS again. Abort if it is still 10.
4. Strip the suffix and check that its VID/PID matches the device. Select the image by PID if the file is dual.
5. `start = 0x08002000`. `end = start + len + 2048`, and Oryx adds another 2048 if that stays ≤ 0x08042000. Reject if `end > 0x08042000`.
6. **Erase:** for `addr = start; addr < end; addr += 2048`, send DNLOAD `[0x41, addr LE32]`, then poll GETSTATUS until the state is no longer DNBUSY (zapp) or equals DNLOAD-IDLE (Oryx, up to 100 polls). Sleep `bwPollTimeout` between polls; zapp sleeps at least 100 ms.
7. **Write:** for each 2048-byte chunk at `addr`:
   - DNLOAD `[0x21, addr LE32]` and poll;
   - DNLOAD `wValue=2` with the chunk;
   - poll until DNLOAD-IDLE.
8. **Leave:** sleep 1 s (zapp), DNLOAD `[0x21, 0x08002000]`, DNLOAD `wValue=2` with length 0, then GETSTATUS. Ignore errors: the device resets and re-enumerates as `3297:1977`.

dfu-util's equivalent is `dfuse_do_dnload` -> `dfuse_dnload_element`: an erase pass, then a write pass, then `dfuse_do_leave` (`dfuse.c` lines 480-575 and 361-375). dfu-util erases only pages listed in the interface's DfuSe memory-layout string and skips erasing "if the location is not in the memory map" (lines 506-509). Ignition's alt-setting string is unknown, so **do not rely on a layout string; erase explicitly** as zapp and Oryx do.

**Worked numbers for the user's file** (65,788-byte payload; `python3 -I` calculation):

| Step | Oryx algorithm | zapp algorithm |
|---|---|---|
| Erase | 35 pages, 0x08002000-0x08013000 | 34 pages, 0x08002000-0x08012800 |
| Write | 33 blocks: 32 x 2048 + 1 x 252 (last at 0x08012000) | same |
| Last byte written | 0x080120FB | same |
| Control transfers | about 101 DNLOADs plus GETSTATUS polls | similar |

At about 1 ms per control transfer plus page-erase time (roughly 20-40 ms per STM32F3 page, INFERRED), expect 2-4 s to flash, dominated by erase polling.

**Differences between the reference implementations, and what Sextant should do:**

| Aspect | Oryx web | zapp | dfu-util | Sextant |
|---|---|---|---|---|
| Erase span | len + 2 pages (if it fits) | len + 1 page | only pages touched | len rounded up to a page, plus 1 page. Never below 0x08002000. |
| Poll condition | until DNLOAD-IDLE, 100 tries | while DNBUSY, sleep ≥ 100 ms | until IDLE/ERROR/MANIFEST | while DNBUSY, honour `bwPollTimeout`, minimum 1 ms, cap 2 s; treat ERROR as a failure |
| Leave | DNLOAD wValue 0, len 0 | SET_ADDRESS start + DNLOAD wValue 2, len 0 | same as zapp | zapp form |
| Suffix check | last 16 bytes or scan | scan | last 16 bytes + CRC | last 16 bytes + **CRC** + VID/PID == device |
| Verify | none | none | none (upload is possible with DfuSe) | optional read-back via DFU_UPLOAD is untested on Ignition (open question) |

Bugs in the old tools, so nobody copies them:
- Wally and wally-cli parse the suffix VID with byte-wrapping arithmetic (`int((suffix[5] << 8) + suffix[4])` on `byte`s). Their "expected" VID/PID is therefore `0x83:0x11`, the low bytes of `0483:df11` (`wally/usb.go` lines 21-22, `dfu.go` lines 98-104).
- Their `bwPollTimeout` parsing ORs instead of shifting (`dfu.go` line 68).

### 8.6 Which tools can flash a Voyager

| Tool | Voyager? | Evidence |
|---|---|---|
| Wally (GUI) | **No.** Matches only `0483:DF11` and HalfKay; its keyboard PIDs do not include 0x1977; base 0x08000000. README: "Wally is no longer maintained". Wiki: "Wally is deprecated and will not work for newer keyboards". | `wally/wally/usb.go` lines 14-44, 76-82; `dfu.go` lines 146-150, 205; README line 1-3; wiki `Linux-install.md` line 91 |
| wally-cli | **No.** Same logic, `planckStartAddress = 0x08000000`; repo archived | `wally-cli/usb.go` lines 9-33; `dfu.go` lines 136-143, 189-217 |
| Keymapp (closed, v1.3.7 installed) | **Yes.** The wiki's udev section is titled "Keymapp Flashing rules for the Voyager" (`3297`, `SYMLINK+="ignition_dfu"`) | wiki `Linux-install.md` lines 68-72; `study/03` section 5 |
| Oryx in Chrome (WebUSB) | **Yes.** On macOS: "browser-based flashing will just work — nothing to set up" | Oryx `$C`; `blog.zsa.io/2206-live-flashing` |
| **zapp** (ZSA, Rust, MIT + Commons Clause, `brew install zapp`) | **Yes.** `zapp flash <file\|Oryx URL>`, `zapp update` (reads the serial number, compares with `/firmware/latest/{layout}`). Uses `nusb` (pure-Rust USB) and `hidapi`. | `zapp/README.md`; `zapp-core/Cargo.toml`; blog `introducing-zapp` (2026-04-07) |
| dfu-util / `make zsa/voyager:<km>:flash` | **Yes**, `dfu-util -d 3297:0791 -a 0 -s 0x08002000:leave -D <bin>` | `rules.mk` line 5; `flash.mk` lines 13-24 |
| `qmk flash -bl ...` with a prebuilt file | **No auto-detection.** QMK's bootloader table lacks `3297:0791`, and its generic STM32 path uses `-s 0x08000000:leave` (wrong base) | `lib/python/qmk/constants.py` lines 80-98; `lib/python/qmk/flashers.py` lines 173-182 |

### 8.7 Can a bad flash brick the Voyager? Recovery

Assessment: **hard to brick, easy to "soft-brick", always recoverable with the reset button**, provided nothing writes below 0x08002000 (INFERRED from the sources below).

- **The bootloader lives outside every erase range.** Ignition sits in 0x08000000-0x08001FFF. ZSA's flashers start at 0x08002000 and never mass-erase. The `rmk-zsa-voyager` README additionally states the bootloader "lives in protected flash and cannot be overwritten" (community claim, unverified).
- **The bootloader runs first on every reset** and checks the A8 line. The reset button and `bootloader_jump()` both drive that path (`voyager.c` lines 308-321). A non-working application therefore cannot prevent entry to DFU through the reset button (INFERRED: the button's wiring to A8 or reset is not documented).
- **Soft-brick cases** (keyboard dead or erratic until reflashed):
  - interrupted flash;
  - a firmware linked at 0x08000000 (for example a generic `stm32-dfu` build) written at 0x08002000. Its vector table points 8 KiB too low, so it hard-faults. zapp explicitly refuses mismatched images "which would brick the keyboard due to mismatched base addresses" (`flash/mod.rs` lines 41-47, 81-101);
  - a GD32/STM32 image mismatch.
  Recovery in every case: press the reset button, then flash a known-good `.bin`. Oryx can always re-download any revision.
- **Truly bricking** would require erasing or writing the bootloader pages through a raw tool (e.g., `dfu-util -s 0x08000000`, if Ignition allowed it) or via SWD. Recovery would then need an SWD probe and an Ignition image, which is not public. **Sextant's flasher must hard-code `minAddress = 0x08002000` and never issue MASS_ERASE.**
- **EEPROM** (keymap-independent settings such as RGB mode and `keyboard_config`) is not erased by flashing. Bootmagic wipes it.

---

## 9. Live USB enumeration (read-only)

At study time the Voyager was **not connected**:
- `system_profiler SPUSBDataType` lists only three built-in `AppleT8122USBXHCI` buses with no devices;
- `ioreg -p IOUSB -l -w0` shows no device below the XHCI controllers;
- `hidutil list` shows only internal Apple services and no VID 0x3297.

All descriptor facts therefore come from the firmware image:
- **normal mode:** `3297:1977`, USB 2.0, EP0 64, strings 1/2/3 = "ZSA Technology Labs"/"Voyager"/"KlgM7/40xJ7M";
- **4 interfaces:** boot keyboard (usage page 0x01/0x06); raw HID **0xFF60/0x61** (Oryx); shared EP for NKRO, consumer, system and mouse; digitizer/PTP for the Navigator trackpad (`study/03` section 2.2).

**Bootloader-mode descriptors (DFU functional descriptor, `wTransferSize`, alt-setting string) are unknown.** Capture them with the read-only commands below the next time the board is in bootloader mode: `ioreg -p IOUSB -l -w0 | grep -A40 '"idProduct" = 1937'` and `system_profiler SPUSBDataType`.

---

## 10. macOS implementation

### 10.1 Options for USB DFU from Swift

| Option | Fit | Notes |
|---|---|---|
| **IOUSBHost.framework** (`IOUSBHostDevice`, `IOUSBHostInterface`, macOS 10.15+) | **good** | Supports `sendDeviceRequest(_:data:bytesTransferred:completionTimeout:)` on EP0 (`IOUSBHostObject.h` lines 104-123). Matching uses `createMatchingDictionary(vendorID:productID:...)` (`IOUSBHostDevice.h` line 35, `IOUSBHostInterface.h` line 40). "Upon creation, exclusive ownership of the IOService will be established" (`IOUSBHostObject.h` lines 25-30). `DeviceCapture` needs `com.apple.vm.device-access` or root (`IOUSBHostDefinitions.h` lines 139-157) and **is not needed**: macOS binds no kernel driver to a DFU-class interface (INFERRED; consistent with ZSA's "just works on Mac" and with zapp on macOS). |
| IOKit `IOUSBLib` (`IOUSBDeviceInterface`/`IOUSBInterfaceInterface` through a CFPlugIn) | works | What libusb, Chrome and nusb-era tools use (`IOKit/usb/IOUSBLib.h`, `kIOUSBDeviceUserClientTypeID` line 82). COM-style and verbose from Swift. Its user clients (`IOUSBDeviceUserClientV2`, `IOUSBInterfaceUserClientV3`) are exactly the ones the sandbox allows (below). |
| libusb 1.0 (LGPL-2.1+) bundled as a dylib | works | dynamic-link compliance obligations; C wrapper; brings nothing a 4-request protocol needs |
| Shell out to `dfu-util` (GPL-2.0+, needs libusb) | works | bundle and sign two extra binaries; parse text output; weak progress and error UX |
| Shell out to `zapp` (MIT + **Commons Clause**: no "Sell") | works | permissible for a free Sextant; extra binary; zapp also talks to Oryx itself |
| Existing Swift wrapper `zsa/USBDeviceSwift` (MIT, 2019) | reference only | stale; demonstrates IOKit USB and HID from Swift |

### 10.2 Entitlements, sandbox, TCC, notarization

- **App Sandbox:** `com.apple.security.device.usb` "allow[s] your sandboxed app to interact with USB devices through USB device access APIs" (Apple docs, `apple-docs/bundleresources_entitlements_com.apple.security.device.usb.json`).
  - The system sandbox profile grants that entitlement `iokit-open-user-client` for **`IOUSBDeviceUserClientV2` and `IOUSBInterfaceUserClientV3`** (plus `IOHIDLibUserClient`) (`/System/Library/Sandbox/Profiles/application.sb` lines 115-123).
  - Whether IOUSBHost.framework's user client resolves to one of those class names is **not verified**. Test it on-device: a sandboxed test app opens `3297:0791` with IOUSBHost, and falls back to IOUSBLib if the open is denied.
- **Hardened runtime:** needs no USB-specific entitlement (INFERRED). Required for notarization.
- **Virtualization (build backend B):** `com.apple.security.virtualization` (Apple docs, macOS 11+).
- **TCC:** none for USB DFU. TCC Input Monitoring applies only to opening HID keyboard, mouse or digitizer interfaces (`study/03` section 0.5 and section 8.3). DFU mode exposes no HID interface at all.
- **Notarization:** standard Developer ID plus `notarytool`. Every Mach-O inside the bundle must be signed with the hardened runtime. That argues against bundling a gcc toolchain inside the `.app`. Download it or use the container image.
- **Distribution (INFERRED):** a local build backend (spawning toolchains or VMs) and USB access fit a **Developer ID, non-App-Store** app best. Start non-sandboxed, then adopt the sandbox once the USB test passes and backend B is confirmed to work sandboxed with the virtualization entitlement.

### 10.3 Recommended flasher design

1. **Device watcher** with `IOServiceAddMatchingNotification`, matching VID `0x3297` and PID in {`0x1977`, `0x1978`, `0x0791`, `0x1791`}.
   - Show "keyboard connected" (normal mode) vs. "bootloader ready".
   - Read `bcdDevice` as the Ignition version.
   - Read the serial number for layout/revision.
2. **Pre-flight**, all hard failures:
   - file ≤ 0x40000 bytes;
   - suffix present, CRC ok, VID `0x3297`;
   - suffix PID == device PID (dual image: select by PID);
   - reject PID `0x1791` unless a GD32 image is present;
   - md5 equals `revision.md5` when the file came from Oryx.
3. **Flash** with the 8.5 algorithm over `IOUSBHostInterface` (interface 0). Use a dedicated serial queue, synchronous `sendDeviceRequest` with a 5 s timeout (as zapp does), and progress = (erased + written) / total.
   - Guard every address against `[0x08002000, 0x08042000)`.
   - Never send `[0x41]` alone.
4. **Leave**, then wait for `3297:1977` to re-appear, with a 10 s timeout. Then optionally verify via the Oryx protocol `GET_FW_VERSION`: the serial should equal the expected `layout/revision` (`study/03` section 3.3).
5. **UX for entering the bootloader:**
   - instruct the user to press the reset button (show a top-down picture pointing at it);
   - or press their `QK_BOOT` key (Sextant knows where it is from the layout);
   - mention Bootmagic as a last resort because it erases settings.
6. **Test oracles during development** (not shipped): `zapp flash file.bin` and `dfu-util -d 3297:0791 -a 0 -s 0x08002000:leave -D file.bin`.

Justification for writing a native implementation:
- the protocol is 4 request types and about 100 transfers;
- two independent open implementations (zapp, Oryx web) pin down Ignition's behaviour;
- it avoids GPL/LGPL/Commons-Clause binaries and the sandbox and notarization friction of helper executables;
- it gives first-class hotplug and progress UX.

Minimal shape of the Swift request (illustrative):

```swift
// DNLOAD (bmRequestType 0x21, bRequest 1), wValue 0 = DfuSe command, wValue 2 = data block, wIndex = interface 0
var req = IOUSBDeviceRequest(bmRequestType: 0x21, bRequest: 0x01, wValue: 0, wIndex: 0, wLength: 5)
let cmd = NSMutableData(bytes: [0x41, 0x00, 0x20, 0x00, 0x08] as [UInt8], length: 5)   // ERASE_PAGE 0x08002000
try interface.__sendDeviceRequest(req, data: cmd, bytesTransferred: nil, completionTimeout: 5)
// then GETSTATUS: bmRequestType 0xA1, bRequest 3, wLength 6 -> [bStatus, poll0, poll1, poll2, bState, iString]
```

---

## 11. Open-source information about the Voyager, and what carries over from the Corne

The user asked to look at open-source information about the keyboard, using the Corne as the open-source comparison.

### 11.1 What is open for the Voyager

| Artifact | Open? | Where |
|---|---|---|
| Firmware (keyboard definition, matrix, LED map, bootloader-jump logic) | **yes, GPL-2.0** | `zsa/qmk_firmware` `keyboards/zsa/voyager` (fork) and `qmk/qmk_firmware` `keyboards/zsa/voyager` (upstream; maintainers drashna and ZSA, readme lines 5-7) |
| ZSA firmware modules (Oryx protocol, Navigator, automouse, ...) | **yes, GPL-2.0** | `zsa/qmk_modules` |
| Flashing CLI | **yes, MIT + Commons Clause** | `zsa/zapp` |
| Legacy flasher | yes (MIT), but no Voyager support | `zsa/wally`, `zsa/wally-cli` |
| Keymapp API demo | yes, MIT | `zsa/kontroll` |
| Oryx-to-QMK build helper | yes, MIT | `zsa/oryx-with-custom-qmk` (fork of poulainpi) |
| Ignition bootloader | **no** (binary on device only) | not in any `github.com/zsa` repo (org listing 2026-10-11) |
| Oryx code generator and server | **no** | the only public trace is its output (section 4) |
| Hardware (schematic, PCB, case) | **no** | no ZSA repo; web search found none. ZSA publishes repair guides ("Robin's repairs", Teardown Tutorial on zsa.io) but no design files. |

Hardware facts the open firmware reveals (all from section 6.2):
- one MCU, in the **left** half (STM32F303, possibly a GD32 variant);
- the **right half is passive**: an MCP23018 I/O expander at I2C 0x20 plus an IS31FL3731 LED driver at 0x77, on the same I2C1 bus (B6/B7) that the left half uses for its own IS31FL3731 at 0x74. The inter-half cable therefore carries I2C (INFERRED);
- 52 keys in a 12x7 matrix with ROW2COL diodes;
- 4 status LEDs (B5, B4 and 2 on the expander);
- a reset or bootloader circuit on A8/A9 with a capacitor.

### 11.2 Corne for comparison

| Aspect | Corne (crkbd) | Voyager | Consequence for Sextant |
|---|---|---|---|
| Hardware licence | **open**: `foostan/crkbd` (pcbs/, cases/, plates/), CC-BY-4.0 + MIT | closed | No Voyager schematics; rely on firmware sources. |
| Keys | 3x6 + 3 thumbs per half (42) | 4x6 + 2 thumbs per half (52) | - |
| MCUs | **one per half**. rev1: Pro Micro ATmega32U4 (Caterina) with serial split on D2. rev4: RP2040 (`bootloader: rp2040`, UF2). | **one MCU for both halves**, right half over I2C | Flash once, not twice; no handedness/EEPROM-hands concerns. |
| Firmware ecosystems | QMK upstream (`keyboards/crkbd/rev1`, `rev4_0`, `rev4_1`), ZMK (wireless variants), Vial, VIA | QMK fork/upstream; a single-keymap Vial port (`study/03` section 7); an RMK (Rust) port (`jpds/rmk-zsa-voyager`, flashes with `dfu-util -d 3297:0791 -a 0 -s 0x08002000:leave`) | Alternative firmwares are flashable with the same DFU path Sextant implements. |
| Configurators | QMK Configurator (cloud build via `api.qmk.fm`), VIA/Vial (live remap), ZMK Studio | Oryx (cloud), Keymapp (view + flash) | QMK Configurator/API can build `zsa/voyager` from upstream, but without ZSA modules (section 7.5 E). |
| Visualisation | `caksoylar/keymap-drawer` parses QMK `keymap.json`/`c2json` | same tool works on a Voyager QMK keymap (INFERRED) | candidate for print/export features |

Sources:
- crkbd: GitHub API for `foostan/crkbd` (licence CC-BY-4.0, repo contents incl. `LICENSE_CC`, `LICENSE_MIT`, `pcbs`); upstream QMK@7a1bbf3 `keyboards/crkbd/rev1/keyboard.json` (`development_board: promicro`, `split.serial.pin: D2`) and `keyboards/crkbd/rev4_1/info.json` (`processor: RP2040`, `bootloader: rp2040`);
- `gh-readmes/caksoylar_keymap-drawer.README.md`;
- `gh-readmes/jpds_rmk-zsa-voyager.README.md`.

What transfers from the Corne world to Sextant:
- the QMK keymap model and generators: `json2c`, `c2json`, community modules;
- the idea of a "flash once, then remap live" firmware (VIA/Vial; `study/03` section 7);
- keymap-drawer-style rendering.

What does not transfer:
- Corne's open PCB data;
- per-half flashing and handedness;
- UF2 or Caterina bootloaders;
- ZMK and BLE.

---

## 12. Open questions and how to resolve them

1. **Ignition descriptors**: `wTransferSize`, `bcdDFUVersion`, `bmAttributes`, the alt-setting string, and whether DFU_UPLOAD (read-back) works. Resolve with a read-only `ioreg`/`system_profiler` capture in bootloader mode.
2. **Which MCU is in the user's board?** `0x0791` (STM32) vs. `0x1791` (GD32). Check the bootloader PID at the next flash. What does Oryx serve to GD32 Voyagers on fw25? Every fw25 file seen has a single STM32 image.
3. **Is `IOUSBHost` usable under the App Sandbox** with only `com.apple.security.device.usb`, or must Sextant use IOUSBLib? Needs a 30-minute on-device test.
4. **Byte-reproducibility** of ZSA builds with gcc 12.2.1 in a Debian container, and real compile time on this Mac (section 7.3 acceptance test).
5. **Generator rules not yet observed:** `endEnter`, `dancesTapAction`, `legacyDualFunctionDances`, `ambidexLT`, `layerLockIdleTimeout`, `debounce`, `disableNKRO`, `lowPollingRate`, `tapCodeDelay`, the international variants, `holdOnOtherKeyPress`, `retroTapping`, `tappingForceHold`, steno. Resolve by finding public layouts that use them via the read-only GraphQL `searchLayouts` and diffing their `/source/` zips, as section 4 did.
   **Decided 2026-10-12 without new samples (ADR 0040):** `layerLockIdleTimeout`, `debounce`, `disableNKRO`, `lowPollingRate`, `tapCodeDelay`, `holdOnOtherKeyPress`, `retroTapping` and `tappingForceHold` (with the mouse, RGB step, Auto Shift and Navigator options) use Sextant's own mapping. `dancesTapAction` and `ambidexLT` write nothing (JRGQm sets both), and neither do the international toggles (the codes carry the locale). Still unobserved: `endEnter`; still refused: `legacyDualFunctionDances` (v1 slice 2.3), steno and `liveTraining` off.
   **Decided 2026-10-14 (ADR 0040, amended):** `legacyDualFunctionDances` builds tap and hold keys that aren't `MT()` or `LT()` as tap dances, and `enableSpaceCadet` writes `SPACE_CADET_ENABLE = yes`. Steno and `liveTraining` are hidden and write nothing: the live connection stays on, and Sextant has no steno keycodes.
6. The meaning of normal-mode PID **0x1978** (zapp lists it as Voyager).

---

## Appendix A: artifacts produced for this report

| Path (under `scratchpad/`) | What |
|---|---|
| `study/02-voyager-flash-constants.json` | machine-readable VID/PIDs, addresses, request codes, suffix layout, endpoints, build pins |
| `scripts/s02/binscan.py` | read-only vector-table, suffix and string scan of a `.bin` (run with `python3 -I`) |
| `scripts/s02/ledcheck.py`, `scripts/s02/ledpairs.py` | Oryx hex colour vs. generated `ledmap` HSV comparison |
| `downloads/oryx-sources-examples/{e5Rrr,m9dpx,XlrR4}/` | three more public fw25 Voyager source zips (sources, build.log, .bin) used for the mapping tables |
| `downloads/qmk-voyager-kbjson/upstream_{rules.mk,readme.md,voyager.h,config.h}` | upstream QMK@7a1bbf3 Voyager files for the fork/upstream comparison |
| `downloads/apple-docs/bundleresources_entitlements_com.apple.security.virtualization.json` | Apple entitlement doc |
| `work/s02_build_targets.py` | `lib/python/qmk/build_targets.py` @93b2b9e (make argument construction) |

Requests to ZSA made by this report: 3 source-zip downloads from `oryx.zsa.io/source/{rev}`, each GET plus its redirect. No GraphQL calls or mutations.

---

## Independent verification

Fact-check date: 2026-10-11. The checker re-derived every claim below from primary sources and did not rely on the author's citations.

**Method:**
- Fresh raw files were fetched from GitHub at the pinned commits into `scratchpad/downloads/factcheck-02/`:
  - `zsa/qmk_firmware@93b2b9e`
  - `zsa/zapp@a1be758`
  - `zsa/wally@dba608a`
  - `zsa/wally-cli@2d0da1e`
  - `qmk/qmk_firmware@7a1bbf3`
- The GitHub API confirmed that `firmware25` is the default branch and that its head is `93b2b9e`.
- The checker wrote its own parsers in `scratchpad/scripts/fc02/` (`suffix.py`, `desc.py`, `bindiff.py`, `mtlt.py`, `grepjs.py`) and ran them with `python3 -I`.
- Offsets in the Oryx bundle are **byte** offsets into `oryx-frontend/index-xhNfd6BI.js` (md5 `34fbb4d6...`). The checker re-located each one.
- Requests made to ZSA by this check:
  - 1 read-only GraphQL `layout` query;
  - 2 GETs of `oryx.zsa.io/firmware/{rev}`;
  - 1 GET of the zapp blog post.

### Results

| # | Claim (short) | Verdict | Evidence |
|---|---|---|---|
| 1 | Suffix VID 0x3297, PID 0x0791, bcdDevice 0xFFFF at 0x100FC; CRC 0x2E4F09FD = ~crc32(file[:-4]); image linked at 0x08002000, reset vector 0x080022BD | **confirmed** (for the build downloaded 2026-10-10 23:25 UTC; see C1) | `fc02/suffix.py` on `layout-bin/firmware.bin`, `oryx-firmware-endpoint/firmware-40xJ7M.bin` and the zip copy gives suffix `ff ff 91 07 97 32 00 01 55 46 44 10 fd 09 4f 2e`, CRC equal to the computed value, MSP 0x20000400, reset 0x080022BD, exactly one `UFD`. `rules.mk:6` `DFU_SUFFIX_ARGS = -v 3297 -p 0791`. `ld/voyager.ld:22` `flash0 (rx) : org = 0x08002000, len = 128k - 0x2000`. `builddefs/common_rules.mk:249-258` (`%.bin` rule calling `$(DFU_SUFFIX) $(DFU_SUFFIX_ARGS) -a`). dfu-util `src/suffix.c:93` `pid = vid = did = 0xffff`. |
| 2 | Ignition 3297:0791 (STM32) / 3297:1791 (GD32); 0x08002000; 2048-byte blocks; DfuSe 0x21/0x41 | **confirmed** | zapp `ids.rs:59-60` (`(ZSA_VID, 0x0791) => IgnitionStm32`, `(ZSA_VID, 0x1791) => IgnitionGd32`), `ids.rs:86-87` (friendly names). `dfu.rs:18` `BLOCK_SIZE = 2048`; `:22-23` `IGNITION_START_ADDRESS = 0x0800_2000`, `IGNITION_END_ADDRESS = 0x0804_2000`; `:37-38` `0x21`/`0x41`. The Oryx bundle at byte 879,852 has `b1=[{57105,1155},{1937,12951},{6033,12951},{8192..8195,12951}]`, `g1=[1937,8192,8193,8194,8195]`, `zj=[6033]`, `ru=2048`, `qj=134225920` (0x08002000), `Qj=134488064` (0x08042000), `eG=33`, `tG=65`. |
| 3 | QMK flash command `dfu-util -d 3297:0791 -a 0 -s 0x08002000:leave` | **confirmed** | `keyboards/zsa/voyager/rules.mk:5` is identical in the fork @93b2b9e and upstream @7a1bbf3 (both files fetched). |
| 4 | `bootloader_jump()` drives A8/A9 high for 500 ms, then resets; Ignition checks A8 high for 100 ms | **confirmed**. The Ignition half rests only on ZSA's source comment, because Ignition is closed source. | `voyager.c:308-321`: "The ignition bootloader is checking for a high signal on A8 for 100ms when powering on the board." A9 and A8 are set push-pull high, then `wait_ms(500)`, `gpio_write_pin_low(A9)` and `NVIC_SystemReset()`. Upstream's `bootloader_jump` is byte-identical. |
| 5 | Wally and wally-cli handle only 0483:DF11 (base 0x08000000) and HalfKay, so no Voyager; Wally is deprecated | **confirmed** | `wally/usb.go:14-44`: the keyboard PIDs are 0x1307/0x4974-6, 0x6060/0xC6CE/F and 0x1969 (no 0x1977); DFU is 0x0483:0xdf11 only. `dfu.go:146-150` waits only for 0483:df11. `dfu.go:204-205` uses `addr := planckStartAddress + page` (0x08000000). `dfu.go:36-39,197` sends mass-erase `[0x41]`. README lines 1-3: "Wally is no longer maintained". The wiki `Linux-install.md` line 91: "Wally is deprecated and will not work for newer keyboards". wally-cli `usb.go:9-33` has the same constants; the GitHub API reports `archived: true`. |
| 6 | Oryx treats Voyager firmware as possibly dual when `qmkVersion != "24.0"`; all fw25 builds are single STM32 images | **confirmed** | Byte 886,804: `const C=v=="voyager"&&T!="24.0";t=new $C(...,C)`. Byte 882,824: `_extractIgnitionFirmare(t)`. Six files have one suffix each: the 5 zip `.bin` files, plus `/firmware/7vbZQA`, which the checker fetched today (md5 `5644bf7a...`, identical to JRGQm's zip `.bin`). Code trace: on PID 6033 (GD32) a single image leaves an empty tail, `_parseDFUSuffix` returns null, and Oryx throws "DFU file suffix invalid." |
| 7 | ZSA builds with `qmk compile -j8`, gcc 12.2.1 (Debian 15:12.2.rel1-1), rooted at `/qmk` | **confirmed**. "Container" is an inference and should be marked INFERRED. | `build.log` line 1: `Ψ Compiling keymap with gmake --jobs=8 --output-sync=target -r -R -f builddefs/build_keyboard.mk ...`. Line 5: `arm-none-eabi-gcc (15:12.2.rel1-1) 12.2.1 20221205`. Compile lines show `/qmk/modules/zsa/...`. `build_targets.py:106-142` builds exactly this argv. |
| 8 | `revision.md5` equals md5 of the downloaded `.bin`, suffix included | **confirmed** at every instant tested (7 of 7). See C1: the value is **not stable over time**. | JSON md5 equals file md5 for KlgM7, JRGQm, e5Rrr, m9dpx and XlrR4. Today, GraphQL `revision.md5` for 40xJ7M = `4f0376c0cf280fdc21e3df5b189685e9`, which equals the md5 of `/firmware/40xJ7M` fetched today. |
| 8b | (implicit, used in section 1, section 7.3 and `02-voyager-flash-constants.json`) The user's 40xJ7M firmware is md5 `4d59bb3d...`, CRC 0x2E4F09FD | **partially-correct**: that was true at 2026-10-10 23:25 UTC and is now stale | `/firmware/40xJ7M` at 2026-10-11 00:12 UTC is 65,804 B with md5 `4f0376c0...` and CRC 0xAC6EC476. GraphQL now returns the new md5. `fc02/bindiff.py` finds only 2 code bytes changed (plus the CRC): 0x4B84 and 0xEE5C, `0x1E` -> `0x09`. That is the DUAL_FUNC_0 placeholder `LT(15,KC_1)` (0x4F1E) becoming `LT(15,KC_F)` (0x4F09). |
| 9 | A Voyager build needs only `lib/chibios`, `lib/printf` and `modules/zsa`; ChibiOS-Contrib is unused | **confirmed** | `.gitmodules:1-30`. Gitlinks @93b2b9e: chibios `be44b330`, printf `c2e3b4e1`, `modules/zsa` `13890cd7`. `platform.mk:316-335` enables contrib only if a `halconf_community.h` exists, and `git ls-tree -r` finds **0** such files in the fork. `build.log` compiles 91 `lib/chibios` units and none from contrib. `lib/fnv` and `lib/lib8tion` are also compiled, but they are in-tree directories, not submodules. |
| 10 | `qmk compile` uses `gmake` if present, else `make`; with `-j>1` it adds `--output-sync=target`, which make 3.81 lacks | **confirmed** | `commands.py:18-26`: `$MAKE` env var first, then `gmake`, then `make`. `:40-42` adds `--output-sync=target` whenever `parallel != 1`, including `-j0`. Local `/usr/bin/make` is GNU Make 3.81 and rejects the flag: "unrecognized option `--output-sync=target'". |
| 11 | The App Sandbox USB entitlement allows only `IOUSBDeviceUserClientV2`/`IOUSBInterfaceUserClientV3` (+ `IOHIDLibUserClient`) | **confirmed** for `application.sb`, but this is incomplete (O3) | `/System/Library/Sandbox/Profiles/application.sb:114-123` (the author's 115-123 is off by one). |
| 12 | Oryx emits `MT()` only for basic tap + single-modifier hold, `LT()` for hold `MO(n)`, and DUAL_FUNC otherwise | **partially-correct** | `fc02/mtlt.py` over all 5 JSON/source pairs found 35 `MT`, 20 `LT`, many DUAL_FUNC, and two exceptions to the stated rule. (a) e5Rrr layer 0 key 50, tap `KC_ENTER` + hold `{"code":"MEH_T"}`, emits **`MEH_T(KC_ENTER)`**: neither MT nor DUAL_FUNC. (b) e5Rrr layer 1 key 25, tap `KC_LEFT_GUI` + hold `KC_LEFT_CTRL`, emits `DUAL_FUNC_0` even though the tap is QK_BASIC. The rule is therefore "tap is a basic **non-modifier** keycode". The placeholder `LT(l,kc)` arguments also change between builds (row 8b). |
| 13 | Bootmagic is matrix [0,1] (top-left key) and resets EEPROM before jumping | **confirmed** | `keyboard.json:26-28` `"matrix": [0, 1]`, which is `k00` (`keyboard.json:163`). `bootmagic.c:35-37` (`eeconfig_disable()`) and `:63-75` (scan, reset, `bootloader_jump()`). `eeconfig.c:180-182` calls `nvm_eeconfig_disable()`, which calls `eeprom_driver_format(false)` and sets the magic to OFF (`nvm_eeconfig.c:66-71`). Neither `voyager.c` nor `zsa/qmk_modules` overrides it. |
| 14 | zapp is ZSA's open-source flasher, supports the Voyager, and downloads `https://oryx.zsa.io/firmware/{revisionId}` | **confirmed** | `zapp-oryx/src/lib.rs:21` `ORYX_API_URL = "https://oryx.zsa.io"`; `:197` `format!("{ORYX_API_URL}/firmware/{revision_id}{}", variant.query())`; `:186-187` `?alt=true` / `?collate=true`. README lines 7 and 20. `LICENSE.md` is the Commons Clause + MIT. Blog `posts.json`: "Introducing Zapp", `date_published` "Tue, 07 Apr 2026". |
| 15 | Erase/write arithmetic: Oryx 35 pages to 0x08013000, zapp 34 to 0x08012800, 33 blocks with the last 252 B at 0x08012000 | **confirmed**, with one nuance (C3) | Oryx `flash()`: `l=a+n.byteLength+ru; if(l>s) throw; l+ru<s&&(l+=ru)`. zapp `dfu.rs:87`: `end = start + len + BLOCK_SIZE`. 65,788 = 32 x 2048 + 252. |
| 16 | Leave: zapp sends SET_ADDRESS(start) + DNLOAD wValue=2 len 0; Oryx sends DNLOAD wValue=0 len 0 | **confirmed** | zapp `dfu.rs:159-168` and `:297-318` (`value: 2, data: &[]`). Oryx `_dfuReboot(){ this._download(new ArrayBuffer(0),0); this._getStatus() }`. |
| 17 | zapp would flash a single STM32 image onto a GD32 (0x1791) Ignition | **confirmed** | `flash/mod.rs:71-101` rejects only STM32-DFU vs Ignition mismatches. `dfu.rs:56-68`: a dual image with no PID match "Fall back to primary". |
| 18 | Normal mode is 3297:1977 with 4 HID interfaces and no DFU runtime interface | **confirmed** | `fc02/desc.py`: device descriptor at 0xF370 (bcdUSB 0x0200, EP0 64, bcdDevice 0x0001); configuration at 0xF2FC with `wTotalLength` 116 and 4 interfaces, all class 0x03 (IF0 boot keyboard 03/01/01). No class 0xFE interface. |
| 19 | RGB LED index equals Oryx index; `LAYOUT()` order is row-interleaved | **confirmed** | `keyboard.json`: `rgb_matrix.layout[i].matrix == layout(k{i}).matrix` for all 52 keys. `layouts.LAYOUT` order is lines 163-214. |
| 20 | "No `EXEC_DFU` macro exists in the fork", so `PROGRAM_CMD` is empty | **partially-correct** | `EXEC_DFU` **does** exist, at `platforms/avr/flash.mk:25` (dfu-programmer). `build_keyboard.mk:553` includes only `platforms/$(PLATFORM_KEY)/flash.mk`, though, so for the ChibiOS Voyager it is undefined, `PROGRAM_CMD` expands empty, and make takes the `MCU_FAMILY == STM32` branch (`chibios/flash.mk:112-113`). The author's conclusion holds. |
| 21 | `qmk flash` cannot auto-detect 3297:0791; its generic STM32 path uses `0x08000000:leave` | **confirmed** | `constants.py` has no `3297`. `flashers.py:180-182`: `'-s', '0x08000000:leave'`. |
| 22 | Fork vs upstream: same `rules.mk`; `keyboard.json` differs only by `tapping.toggle` | **confirmed** | `diff`: the only other differences are reordered RGB-animation keys. `bootloader_jump` is identical. Upstream commit 7a1bbf3 is dated 2026-10-02. |
| 23 | Toolchain and container facts: `qmk_toolchains` v15.2.0-1 macOS ARM64 asset 139.1 MB; Apple Containerization Apache-2.0, tag 0.49.0 | **confirmed** | GitHub API: `qmk_toolchains-gcc15.2.0-host_macosARM64.tar.zst` is 139,100,012 B. `apple/containerization` tags start at `0.49.0`. The newest GitHub *Release* object is 0.33.3, which explains why a release listing may disagree. |

### Corrections

- **C1. A revision's firmware is not immutable** (affects section 0 item 1, section 1, section 7.3, section 8.4 and the constants JSON).
  - Between 2026-10-10 23:25 UTC and 2026-10-11 00:12 UTC, Oryx rebuilt revision `40xJ7M`, and both the served `.bin` and `revision.md5` changed. The old md5 was `4d59bb3d...` (CRC 0x2E4F09FD); the new one is `4f0376c0...` (CRC 0xAC6EC476). The size and behaviour are the same.
  - What triggered the rebuild is unknown. It may have been the concurrent browser session opening the layout, or a server-side recompile (INFERRED).
  - Consequences for Sextant:
    - Fetch `revision.md5` and the `.bin` together, then compare.
    - Never cache firmware keyed only by revision hashId.
    - Treat `user_build.md5` and `crc` in `02-voyager-flash-constants.json` as a historical sample, not as the identity of the revision.
- **C2. The byte-reproducibility acceptance test in section 7.3 needs adjusting.** The generator picks the DUAL_FUNC placeholder keycode afresh for each build: `LT(15,KC_1)` became `LT(15,KC_F)`. Two consequences:
  - A rebuild only matches if its sources come from the **same** zip as the `.bin` being compared.
  - Section 4.8's golden tests must normalise the placeholder `LT(l,kc)` **arguments**, not only the `DUAL_FUNC_n` numbering.
- **C3. Oryx's extra erase page has a strict bound.** Oryx adds the second extra erase page only if `l + 2048 < 0x08042000` (strict `<`), not `<=` as section 8.5 step 5 says.
- **C4. Section 8.5 step 3 mis-describes zapp.** zapp tests `status.b_status == DFU_ERROR` (`dfu.rs:103,108`). That compares **bStatus** with the *state* constant 0x0A, which is a zapp bug, so zapp effectively never clears dfuERROR. Oryx tests `.state==10` correctly but does not re-check after CLRSTATUS. The step as written ("bState == 10, CLRSTATUS, re-check, abort") is the right design, but neither reference implements it.
- **C5. The MT/LT rule needs refining** (section 4.3 and section 4.8 bullet 3):
  - **Mod-tap** applies when the tap is a basic non-modifier keycode with no modifiers, and the hold is one plain modifier keycode.
  - **Layer-tap** applies to the same kind of tap with hold `MO(n)`.
  - **Combined-modifier mod-taps** have a hold code that is itself a `*_T` mod-tap macro and are emitted as `HOLD_T(tap)`. Observed: `MEH_T`. `HYPR_T`, `ALL_T`, `LCA_T` and similar are INFERRED.
  - **DUAL_FUNC** covers everything else, including the case where the tap is a modifier key.
- **C6. Sandbox line numbers.** The `application.sb` USB rule is at lines 114-123 (HID+USB `IOHIDLibUserClient` at 114-117, USB at 118-123).

### Important omissions

- **O1. Neither reference flasher treats dfuERROR as fatal, and zapp can hang.**
  - zapp's data-block poll is `while b_state != DFU_DNIDLE` with no cap (`dfu.rs:292`), so a device stuck in state 10 spins forever.
  - Oryx's `_waitIdle` gives up after 100 polls and **continues silently**.
  - Sextant's planned "cap polls, ERROR = failure" is therefore a deliberate deviation from both references, not a copy. Write it down as such and test it.
- **O2. zapp accepts any matching window, not only the file end.**
  - zapp scans the whole file for any 16-byte window with `UFD` at offset 8 and a non-zero PID (`dfu_bin.rs:24-57`).
  - Oryx's dual-image path scans from offset 0 in the same way.
  - Either can mis-split a payload that happens to contain `UFD` at the right place. Keep section 8.5's "last 16 bytes + CRC" rule.
  - In the non-dual path (fw 24.0), Oryx checks only that the suffix VID/PID is in its known list `b1`, not that it equals the connected device. It would accept a 0x0791 image on a 0x1791 device.
- **O3. macOS 27 has a dedicated sandbox-friendly USB API that section 10 does not mention.**
  - The installed SDK ships `AccessoryAccess.framework` (`AAUSBAccessoryManager`, `AAUSBAccessory`, `API_AVAILABLE(macos(27.0))`).
  - Its `-open` returns an `IOUSBHostDevice`, and the manager requires the `com.apple.developer.accessory-access.usb` entitlement (`AAUSBAccessoryManager.h:32-35`, `AAUSBAccessory.h:64-80`). The manager presents UI on the app's behalf.
  - `/System/Library/Sandbox/Profiles/frameworks.sb:23-28` grants that entitlement `iokit-open-user-client` for `AppleUSBHostDeviceUserClient` and `AppleUSBHostFrameworkDeviceClient`.
  - Apple's own `com.apple.ptpcamerad.sb:68-71` lists `AppleUSBHostDeviceUserClient` and `AppleUSBHostInterfaceUserClient`. That suggests IOUSBHost.framework objects use **AppleUSBHost\*** user clients, which are **not** in `application.sb`'s `com.apple.security.device.usb` allow-list. Plain IOUSBHost under the classic USB entitlement would then likely be denied (INFERRED; confirm on-device).
  - Sandbox options are therefore (a) IOUSBLib under `device.usb`, or (b) AccessoryAccess + `accessory-access.usb`. A `com.apple.developer.*` entitlement may need Apple approval (INFERRED).
  - Section 12, question 3 should add this.
- **O4. Bootmagic formats EEPROM; it does not just invalidate it.** It calls `eeprom_driver_format(false)` before setting the magic to OFF (`nvm_eeconfig.c:66-71`). The UX copy "erases settings" is accurate.
- **O5. The firmware endpoint can serve a newer build than a cached source zip** (follows from C1). Download the `.bin` and `/source/{rev}` close together if both are needed.
