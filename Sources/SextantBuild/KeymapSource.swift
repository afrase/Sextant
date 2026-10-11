import Foundation
import SextantDomain

/// Lines of C plus the key each key-specific line came from (1-based line numbers).
struct SourceText {
    private(set) var lines: [String] = []
    private(set) var sourceMap: [Int: KeyRef] = [:]

    /// Adds one or more lines; each maps to `key` when given.
    mutating func add(_ text: String, _ key: KeyRef? = nil) {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            lines.append(String(line))
            if let key { sourceMap[lines.count] = key }
        }
    }

    var text: String { lines.joined(separator: "\n") + "\n" }
}

/// Renders `keymap.c` from a ``KeymapPlan``: Oryx's sections in Oryx's order. The keymap lists one key per line so a
/// compiler error on a keycode maps to its key.
struct KeymapSource {
    let plan: KeymapPlan
    let features: Features
    let board: BoardDefinition
    private var layout: KeyboardLayout { plan.layout }

    func render() -> SourceText {
        var out = SourceText()
        header(&out)
        keymaps(&out)
        if features.chordalHold { chordalHold(&out) }
        combos(&out)
        if features.perKeyTappingTerm { tappingTerms(&out) }
        if features.capsLockStatus {
            out.add("\nbool capslock_active = false;\n\nbool led_update_user(led_t led_state) {")
            out.add("  capslock_active = led_state.caps_lock;\n  return true;\n}")
        }
        out.add(KeymapTemplates.rgbHelpers)
        lighting(&out)
        if features.pointing == .trackball {
            out.add(KeymapTemplates.trackballExterns)
            if features.automouseLayer != nil { out.add(KeymapTemplates.trackballAutomouse) }
        }
        if !plan.dances.isEmpty { TapDanceSource(dances: plan.dances).render(&out) }
        processRecord(&out)
        return out
    }

    private func header(_ out: inout SourceText) {
        out.add("#include QMK_KEYBOARD_H\n#include \"version.h\"")
        if !plan.localeCodes.isEmpty { out.add("#include \"i18n.h\"") }
        out.add("#define MOON_LED_LEVEL LED_LEVEL\n#ifndef ZSA_SAFE_RANGE\n#define ZSA_SAFE_RANGE SAFE_RANGE\n#endif\n")
        out.add("enum custom_keycodes {")
        out.add("  RGB_SLD = ZSA_SAFE_RANGE,")
        for (i, use) in plan.macros.enumerated() { out.add("  ST_MACRO_\(i),", use.key) }
        for color in plan.colors { out.add("  \(color.name),", color.key) }
        out.add("};\n")
        if !plan.dances.isEmpty {
            out.add("enum tap_dance_codes {")
            for (i, dance) in plan.dances.enumerated() { out.add("  DANCE_\(i),", dance.key) }
            out.add("};\n")
        }
        for (i, dual) in plan.dualFunctions.enumerated() { out.add("#define DUAL_FUNC_\(i) \(dual.placeholder)", dual.key) }
    }

    private func keymaps(_ out: inout SourceText) {
        out.add("\nconst uint16_t PROGMEM keymaps[][MATRIX_ROWS][MATRIX_COLS] = {")
        for (li, layer) in layout.layers.enumerated() {
            out.add("  [\(li)] = LAYOUT_\(board.name)(")
            for (n, index) in board.layoutOrder.enumerated() {
                let key = layer.keys[index]
                let slot = key.filledSlots.count == 1 ? key.filledSlots[0] : nil
                out.add(
                    "    \(plan.tokens[li][index])\(n < board.layoutOrder.count - 1 ? "," : "")",
                    KeyRef(layer: li, index: index, slot: slot))
            }
            out.add("  ),")
        }
        out.add("};")
    }

    /// Chordal hold: each key's hand; thumbs (below the four main rows) are exempt when the setting says so.
    private func chordalHold(_ out: inout SourceText) {
        let excludeThumbs = features.flag("chordalHoldExcludeThumbs")
        let hands = board.layoutOrder.map { index in
            let key = board.keys[index]
            // shortcut: thumb = below the main rows and hand = matrix half (Voyager); use board fields for a second board.
            if excludeThumbs && key.qmkPosition.y >= 4 { return "'*'" }
            return key.matrixRow < board.matrixRows / 2 ? "'L'" : "'R'"
        }
        out.add("\nconst char chordal_hold_layout[MATRIX_ROWS][MATRIX_COLS] PROGMEM = LAYOUT(")
        out.add("  " + hands.joined(separator: ", "))
        out.add(");")
    }

    private func combos(_ out: inout SourceText) {
        guard !plan.combos.isEmpty else { return }
        out.add("")
        for (i, combo) in plan.combos.enumerated() {
            out.add("const uint16_t PROGMEM combo\(i)[] = { \(combo.keys.joined(separator: ", ")), COMBO_END};")
        }
        out.add("\ncombo_t key_combos[COMBO_COUNT] = {")
        for (i, combo) in plan.combos.enumerated() { out.add("    COMBO(combo\(i), \(combo.output)),") }
        out.add("};")
    }

    /// Per-key tapping terms. QMK keys them by keycode, so identical keys share the first one's term.
    private func tappingTerms(_ out: inout SourceText) {
        out.add("\nuint16_t get_tapping_term(uint16_t keycode, keyrecord_t *record) {\n    switch (keycode) {")
        var seen: Set<String> = []
        for (li, layer) in layout.layers.enumerated() {
            for (ki, key) in layer.keys.enumerated() {
                guard let term = key.tappingTerm, seen.insert(plan.tokens[li][ki]).inserted else { continue }
                let delta = term - features.tappingTerm
                let ref = KeyRef(layer: li, index: ki)
                out.add("        case \(plan.tokens[li][ki]):", ref)
                out.add("            return g_tapping_term \(delta < 0 ? "-" : "+")\(abs(delta));", ref)
            }
        }
        out.add("        default:\n            return g_tapping_term;\n    }\n}")
    }

    /// The per-layer LED map: a key's glow colour, else its layer's colour, else off.
    private func lighting(_ out: inout SourceText) {
        let lit = layout.layers.indices.filter { li in
            layout.layers[li].color != nil || layout.layers[li].keys.contains { $0.glowColor != nil }
        }
        if !lit.isEmpty {
            out.add("const uint8_t PROGMEM ledmap[][RGB_MATRIX_LED_COUNT][3] = {")
            for li in lit {
                let cells = layout.layers[li].keys.map { key in
                    (key.glowColor ?? layout.layers[li].color).map { QMKCodes.HSV($0).triple } ?? "{0,0,0}"
                }
                out.add("    [\(li)] = { \(cells.joined(separator: ", ")) },")
            }
            out.add("};")
            out.add(KeymapTemplates.setLayerColor)
        }
        out.add(KeymapTemplates.indicatorsStart)
        for li in lit { out.add("      case \(li):\n        set_layer_color(\(li));\n        break;") }
        out.add(KeymapTemplates.indicatorsDefault)
        if features.capsLockStatus {
            for (li, layer) in layout.layers.enumerated() {
                for (ki, key) in layer.keys.enumerated() {
                    guard let color = key.lockGlowColor else { continue }
                    let hsv = QMKCodes.HSV(color)
                    out.add(
                        """
                          if (capslock_active && biton32(layer_state) == \(li)) {
                            RGB rgb = hsv_to_rgb_with_value((HSV) { \(hsv.h), \(hsv.s), \(hsv.v) });
                            rgb_matrix_set_color( \(ki), rgb.r, rgb.g, rgb.b );
                          }
                        """, KeyRef(layer: li, index: ki))
                }
            }
        }
        out.add("  return true;\n}\n")
    }

    private func processRecord(_ out: inout SourceText) {
        let checks =
            (features.usesMouseKeys ? ["IS_MOUSE_KEYCODE(QK_MODS_GET_BASIC_KEYCODE(keycode))"] : [])
            + (features.usesConsumerKeys || !features.usesMouseKeys ? ["IS_CONSUMER_KEYCODE(QK_MODS_GET_BASIC_KEYCODE(keycode))"] : [])
        out.add(KeymapTemplates.modsCase(checks.joined(separator: " || ")))
        for (i, use) in plan.macros.enumerated() {
            out.add("    case ST_MACRO_\(i):", use.key)
            out.add("    if (record->event.pressed) {")
            out.add("      \(Self.sendString(use.macro))", use.key)
            out.add("    }")
            out.add("    break;")
        }
        out.add("")
        for (i, dual) in plan.dualFunctions.enumerated() { dualFunction(i, dual, &out) }
        out.add("    case RGB_SLD:\n      if (record->event.pressed) {\n        rgblight_mode(1);\n      }\n      return false;")
        for color in plan.colors {
            out.add("    case \(color.name):", color.key)
            out.add("      if (record->event.pressed) {")
            out.add("        rgblight_mode(1);")
            out.add("        rgblight_sethsv(\(color.hsv.h),\(color.hsv.s),\(color.hsv.v));", color.key)
            out.add("      }")
            out.add("      return false;")
        }
        out.add("  }\n  return true;\n}")
    }

    private func dualFunction(_ i: Int, _ dual: KeymapPlan.DualFunction, _ out: inout SourceText) {
        let tapRef = KeyRef(layer: dual.key.layer, index: dual.key.index, slot: .tap)
        let holdRef = KeyRef(layer: dual.key.layer, index: dual.key.index, slot: .hold)
        // The plan only admits actions that have statements.
        let tap = QMKCodes.statements(dual.tap), hold = QMKCodes.statements(dual.hold)
        out.add("    case DUAL_FUNC_\(i):", dual.key)
        out.add("      if (record->tap.count > 0) {")
        out.add("        if (record->event.pressed) {")
        out.add("          \(tap?.press ?? "")", tapRef)
        out.add("        } else {")
        out.add("          \(tap?.release ?? tap?.press ?? "")", tapRef)
        out.add("        }")
        out.add("      } else {")
        out.add("        if (record->event.pressed) {")
        out.add("          \(hold?.press ?? "")", holdRef)
        out.add("        } else {")
        out.add("          \(hold?.release ?? hold?.press ?? "")", holdRef)
        out.add("        }")
        out.add("      }")
        out.add("      return false;")
    }

    /// `SEND_STRING(...)` for a macro: each step's delay follows it; Oryx's Alt-code macros hold Left Alt throughout.
    static func sendString(_ macro: Macro) -> String {
        var s = ""
        for (i, step) in macro.steps.enumerated() {
            s += QMKCodes.macroStep(step)
            if i < macro.steps.count - 1 { s += step.delay > 0 ? "SS_DELAY(\(step.delay))  " : " " }
        }
        if macro.holdsOption { s = "SS_LALT(\(s) )" }
        if macro.endsWithEnter {
            if let last = macro.steps.last, last.delay > 0 { s += "  SS_DELAY(\(last.delay))" }
            s += " SS_TAP(X_ENTER)"
        }
        return s.isEmpty ? "SEND_STRING(\"\");" : "SEND_STRING(\(s));"
    }
}
