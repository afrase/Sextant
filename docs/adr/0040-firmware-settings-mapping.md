# 40. Firmware settings mapping: Sextant's own lines where Oryx's were never seen

Status: accepted, 2026-10-12. Amends 0020 and 0030.

## Context
ADR 0020 refuses any setting whose QMK output was never observed in Oryx's sources, and ADR 0030 put debounce, tap code delay, one-shot tap toggle and several Navigator options on the MVP page before the generator could write them, so changing one made every build refuse. Research 02 §12 item 5 lists the settings Oryx's five samples never show. On 2026-10-12 the user chose Sextant's own mapping for them over fetching more public Oryx layouts (no downloads, no new ZSA material to strip before a public push).

## Decision
- **Sextant writes these settings itself.** Every name below was checked in the pinned firmware (ZSA's fork 93b2b9e, modules 13890cd):

  | Setting | Output |
  |---|---|
  | `debounce` | `DEBOUNCE n` |
  | `tapCodeDelay` | `TAP_CODE_DELAY 10` |
  | `oneShotTapToggle` | `ONESHOT_TAP_TOGGLE n` |
  | `retroTapping`, `holdOnOtherKeyPress` | `RETRO_TAPPING`, `HOLD_ON_OTHER_KEY_PRESS` |
  | `tappingForceHold` | `QUICK_TAP_TERM 0` (the pinned firmware has no `TAPPING_FORCE_HOLD`) |
  | `autoshiftModifiers` | `AUTO_SHIFT_MODIFIERS` |
  | `autoshiftEnableSpecial`, `…Numeric`, `…Alpha`, `…Tab` off | `NO_AUTO_SHIFT_SYMBOLS`, `NO_AUTO_SHIFT_NUMERIC`, `NO_AUTO_SHIFT_ALPHA`, `NO_AUTO_SHIFT_TAB` |
  | `mouseMaxSpeed`, `mouseTimeToMax`, `mouseWheel{Interval,MaxSpeed,TimeToMaxSpeed,Delay}` | `MOUSEKEY_MAX_SPEED`, `MOUSEKEY_TIME_TO_MAX`, `MOUSEKEY_WHEEL_{INTERVAL,MAX_SPEED,TIME_TO_MAX,DELAY}` |
  | `rgbHueStep`, `rgbBriStep` | `RGB_MATRIX_HUE_STEP`, `RGB_MATRIX_VAL_STEP` |
  | `rgbUsbSuspend` off | `#undef RGB_MATRIX_SLEEP` (keyboard.json turns it on) |
  | `layerLockIdleTimeout` (seconds) | `LAYER_LOCK_IDLE_TIMEOUT` in ms |
  | `lowPollingRate` | `USB_POLLING_INTERVAL_MS 10` |
  | `disableNKRO` | `NKRO_ENABLE = no` in rules.mk, after keyboard.json's |
  | `disableUsbStartupCheck` | `NO_USB_STARTUP_CHECK = yes` in rules.mk |
  | Navigator `rotation` | `NAVIGATOR_TRACKPAD_ROTATION` or `NAVIGATOR_TRACKBALL_ROTATION`, in degrees 0–359 |
  | trackball `scrollOnly` | `NAVIGATOR_TRACKBALL_SCROLL_ONLY` |
  | trackball `aimSpeed` Slow / Fast | `NAVIGATOR_AIM_DIVIDER` 4 / 2 (the module's 3 is Normal) |
  | trackball `turboSpeed` Slow / Fast | `NAVIGATOR_TURBO_MULTIPLIER` 2 / 4 (the module's 3 is Normal) |
  | trackball `aimLayers`, `turboLayers`, `dragScrollLayers` | `NAVIGATOR_{AIM,TURBO,DRAG_SCROLL}_LAYERS { 1, 2 }` |
  | trackpad `oneShotAutoMouse`, `oneShotAutoMouseTimeout` (seconds) | `AUTOMOUSE_ONESHOT`, `AUTOMOUSE_ONESHOT_TIMEOUT` in ms, with an automouse layer |

- **Only away from the default.** A setting writes nothing at its catalog default, even when an import stores the default; a slider that is off by default (one-shot tap toggle, the one-shot auto-mouse timeout) writes whenever it is stored. Sextant's `config.h` lines come after Oryx's, so Oryx's order and the five goldens stay byte-identical. Numbers are `#undef`'d first, because the Voyager's config.h and QMK's generated info_config.h define some of them.
- **Values Oryx never showed.** Tap code delay is 10 ms. The lower polling rate is 10 ms, the fastest interval USB allows a low-speed device, so hosts that expect only those keep up. Rotation is brought into 0–359 because C's `%` keeps the sign: -90 would take the trackball module's float path instead of its right-angle one. Punctuation uses `NO_AUTO_SHIFT_SYMBOLS`, since `NO_AUTO_SHIFT_SPECIAL` also drops Tab, which has its own toggle.
- **Still refused (ADR 0020):** `liveTraining` off (it probably drops `zsa/oryx`, which Sextant's live view, Keymapp and the RGB preview need), `stenography` and `geminipr` (Sextant has no steno keycodes), and one-shot auto-mouse on the trackball (it runs QMK's own auto mouse, which has no one-shot mode; moving it to `zsa/automouse` would leave Oryx's trackball output). `enableSpaceCadet` and `legacyDualFunctionDances` move to v1 slice 2.3, which touches the key code. `ambidexLT`, `dancesTapAction` and the locale toggles still write nothing.
- **Validation (amends 0020):** a stored value must have its setting's type (a toggle a Bool, a slider a number, a picker a list), and a Navigator layer list must name layers that exist; anything else is refused by name, like a number out of range.
- **Per-key tapping terms** offset `TAPPING_TERM` unless the layout uses dynamic tapping term keys. Only that feature declares `g_tapping_term`, so per-key terms without those keys failed to compile; XlrR4, Oryx's one sample with per-key terms, has both, and its output is unchanged.
- **Proof:** a table test checks each setting's lines, alone and away from its default, and that the default writes nothing. A completeness check ties the table to every setting the Voyager shows. Layouts with every written setting changed, one per Navigator, compile under the real toolchain, and so do JRGQm, m9dpx and XlrR4.

## Consequences
- ADR 0030's gap is closed: every setting on the MVP page builds.
- A layout imported with one of these settings may build differently from Oryx's own build. An unchanged import keeps Oryx's serial, so Keymapp and Oryx can't tell the two firmwares apart.
- The catalog's mouse defaults are QMK's, but the Voyager sets its own pointer speed (7), acceleration (60) and delay (0), and ties the wheel's interval, speed and acceleration to the pointer's. At the catalog default nothing is written and the board's values apply, as in Oryx's builds; any change replaces them. The v1 settings page should say so.
- The lower polling rate also slows the Navigator, which shares the interval. The tap code delay also spaces each character of a macro by 10 ms.
- NKRO, polling and the startup check can only be checked on the board. The trackball options can't be tried at all: the user has a trackpad.
