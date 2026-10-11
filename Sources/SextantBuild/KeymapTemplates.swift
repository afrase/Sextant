import Foundation
import SextantDomain

/// The fixed parts of Oryx's `keymap.c` (firmware 25), kept verbatim so the Oryx live protocol, Keymapp and the
/// Navigator behave as with Oryx's own builds.
enum KeymapTemplates {
    static let rgbHelpers = """

        extern rgb_config_t rgb_matrix_config;

        RGB hsv_to_rgb_with_value(HSV hsv) {
          RGB rgb = hsv_to_rgb( hsv );
          float f = (float)rgb_matrix_config.hsv.v / UINT8_MAX;
          return (RGB){ f * rgb.r, f * rgb.g, f * rgb.b };
        }

        void keyboard_post_init_user(void) {
          rgb_matrix_enable();
        }

        """

    static let setLayerColor = """

        void set_layer_color(int layer) {
          for (int i = 0; i < RGB_MATRIX_LED_COUNT; i++) {
            HSV hsv = {
              .h = pgm_read_byte(&ledmap[layer][i][0]),
              .s = pgm_read_byte(&ledmap[layer][i][1]),
              .v = pgm_read_byte(&ledmap[layer][i][2]),
            };
            if (!hsv.h && !hsv.s && !hsv.v) {
                rgb_matrix_set_color( i, 0, 0, 0 );
            } else {
                RGB rgb = hsv_to_rgb_with_value(hsv);
                rgb_matrix_set_color(i, rgb.r, rgb.g, rgb.b);
            }
          }
        }

        """

    static let indicatorsStart = """
        bool rgb_matrix_indicators_user(void) {
          if (rawhid_state.rgb_control) {
              return false;
          }
          if (!keyboard_config.disable_layer_led) {
            switch (biton32(layer_state)) {
        """

    static let indicatorsDefault = """
             default:
                if (rgb_matrix_get_flags() == LED_FLAG_NONE) {
                  rgb_matrix_set_color_all(0, 0, 0);
                }
            }
          } else {
            if (rgb_matrix_get_flags() == LED_FLAG_NONE) {
              rgb_matrix_set_color_all(0, 0, 0);
            }
          }

        """

    /// Mouse and consumer keys with modifiers, applied in two reports.
    static func modsCase(_ check: String) -> String {
        """

        bool process_record_user(uint16_t keycode, keyrecord_t *record) {
          switch (keycode) {
          case QK_MODS ... QK_MODS_MAX:
            // Mouse and consumer keys (volume, media) with modifiers work inconsistently across operating systems,
            // this makes sure that modifiers are always applied to the key that was pressed.
            if (\(check)) {
              if (record->event.pressed) {
                add_mods(QK_MODS_GET_MODS(keycode));
                send_keyboard_report();
                wait_ms(2);
                register_code(QK_MODS_GET_BASIC_KEYCODE(keycode));
                return false;
              } else {
                wait_ms(2);
                del_mods(QK_MODS_GET_MODS(keycode));
              }
            }
            break;
        """
    }

    // MARK: Navigator trackball (as in Oryx's trackball sources)

    static let trackballKeycodes = """
          DRAG_SCROLL,
          NAVIGATOR_INC_CPI,
          NAVIGATOR_DEC_CPI,
          NAVIGATOR_TURBO,
          NAVIGATOR_AIM
        """

    static let trackballExterns = """
        extern bool set_scrolling;
        extern bool navigator_turbo;
        extern bool navigator_aim;
        """

    static let trackballAutomouse = """
        void pointing_device_init_user(void) {
          set_auto_mouse_enable(true);
        }

        bool is_mouse_record_user(uint16_t keycode, keyrecord_t* record) {
          // Treat all keys as mouse keys when in the automouse layer so that any key set resets the timeout without leaving the layer.
          if (!layer_state_is(AUTO_MOUSE_TARGET_LAYER)){
            // When depressing a mouse key with a LT key at the same time, the mouse key tracker is not decremented.
            // This is a workaround to fix that
            if (IS_MOUSE_KEYCODE(keycode) && !record->event.pressed) {
              return true;
            }
            return false;
          }
          else {
            return false;
          }
        }

        """

    static let trackballCases = """
            case DRAG_SCROLL:
              if (record->event.pressed) {
                set_scrolling = true;
              } else {
                set_scrolling = false;
              }
              return false;
          case NAVIGATOR_TURBO:
            if (record->event.pressed) {
              navigator_turbo = true;
            } else {
              navigator_turbo = false;
            }
            return false;
          case NAVIGATOR_AIM:
            if (record->event.pressed) {
              navigator_aim = true;
            } else {
              navigator_aim = false;
            }
            return false;
          case NAVIGATOR_INC_CPI:
            if (record->event.pressed) {
                pointing_device_set_cpi(1);
            }
            return false;
          case NAVIGATOR_DEC_CPI:
            if (record->event.pressed) {
                pointing_device_set_cpi(0);
            }
            return false;
        """
}

/// Tap dances in Oryx's shape: `tap` is a single tap, `hold` a single hold, `doubleTap` a double tap (two taps of
/// `tap` when unset), `tapHold` a tap then hold.
struct TapDanceSource {
    let dances: [KeymapPlan.Dance]

    func render(_ out: inout SourceText) {
        out.add(Self.preamble(count: dances.count))
        for (n, dance) in dances.enumerated() { render(n, dance, &out) }
        out.add("\ntap_dance_action_t tap_dance_actions[] = {")
        for (n, dance) in dances.enumerated() {
            let onDance = dance.slots.tap == nil ? "NULL" : "on_dance_\(n)"
            out.add("        [DANCE_\(n)] = ACTION_TAP_DANCE_FN_ADVANCED(\(onDance), dance_\(n)_finished, dance_\(n)_reset),", dance.key)
        }
        out.add("};")
    }

    private func render(_ n: Int, _ dance: KeymapPlan.Dance, _ out: inout SourceText) {
        func ref(_ slot: KeySlot) -> KeyRef { KeyRef(layer: dance.key.layer, index: dance.key.index, slot: slot) }
        let key = dance.slots
        // The plan admits only dances whose actions have statements and whose tap is a key.
        let tap = key.tap.flatMap(QMKCodes.statements)
        let tapCode = key.tap.map { QMKCodes.wrap($0.code, $0.modifiers) } ?? ""
        let steps: [(step: String, slot: KeySlot, statements: (press: String, release: String?))] = [
            tap.map { ("SINGLE_TAP", .tap, $0) },
            key.hold.flatMap(QMKCodes.statements).map { ("SINGLE_HOLD", .hold, $0) },
            key.doubleTap.flatMap(QMKCodes.statements).map { ("DOUBLE_TAP", .doubleTap, $0) }
                ?? tap.map { ("DOUBLE_TAP", .tap, (press: $0.press + " " + $0.press, release: $0.release)) },
            key.tapHold.flatMap(QMKCodes.statements).map { ("DOUBLE_HOLD", .tapHold, $0) },
        ].compactMap { $0 }

        if tap != nil { out.add("void on_dance_\(n)(tap_dance_state_t *state, void *user_data);") }
        out.add("void dance_\(n)_finished(tap_dance_state_t *state, void *user_data);")
        out.add("void dance_\(n)_reset(tap_dance_state_t *state, void *user_data);\n")
        if tap != nil {
            out.add("void on_dance_\(n)(tap_dance_state_t *state, void *user_data) {\n    if(state->count == 3) {")
            out.add(String(repeating: "        tap_code16(\(tapCode));\n", count: 3) + "    }", ref(.tap))
            out.add("    if(state->count > 3) {\n        tap_code16(\(tapCode));\n    }\n}\n", ref(.tap))
        }
        out.add("void dance_\(n)_finished(tap_dance_state_t *state, void *user_data) {")
        out.add("    dance_state[\(n)].step = dance_step(state);\n    switch (dance_state[\(n)].step) {")
        for s in steps { out.add("        case \(s.step): \(s.statements.press) break;", ref(s.slot)) }
        if tap != nil { out.add("        case DOUBLE_SINGLE_TAP: tap_code16(\(tapCode)); register_code16(\(tapCode));", ref(.tap)) }
        out.add("    }\n}\n")
        out.add("void dance_\(n)_reset(tap_dance_state_t *state, void *user_data) {\n    wait_ms(10);")
        out.add("    switch (dance_state[\(n)].step) {")
        for s in steps { if let release = s.statements.release { out.add("        case \(s.step): \(release) break;", ref(s.slot)) } }
        if tap != nil { out.add("        case DOUBLE_SINGLE_TAP: unregister_code16(\(tapCode)); break;", ref(.tap)) }
        out.add("    }\n    dance_state[\(n)].step = 0;\n}")
    }

    private static func preamble(count: Int) -> String {
        """

        typedef struct {
            bool is_press_action;
            uint8_t step;
        } tap;

        enum {
            SINGLE_TAP = 1,
            SINGLE_HOLD,
            DOUBLE_TAP,
            DOUBLE_HOLD,
            DOUBLE_SINGLE_TAP,
            MORE_TAPS
        };

        static tap dance_state[\(count)];

        uint8_t dance_step(tap_dance_state_t *state);

        uint8_t dance_step(tap_dance_state_t *state) {
            if (state->count == 1) {
                if (state->interrupted || !state->pressed) return SINGLE_TAP;
                else return SINGLE_HOLD;
            } else if (state->count == 2) {
                if (state->interrupted) return DOUBLE_SINGLE_TAP;
                else if (state->pressed) return DOUBLE_HOLD;
                else return DOUBLE_TAP;
            }
            return MORE_TAPS;
        }

        """
    }
}
