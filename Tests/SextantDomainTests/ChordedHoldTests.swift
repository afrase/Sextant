import SextantDomain
import Testing

/// A modifier hold the key editor writes as one modifier keycode chorded with the rest (ADR 0027).
struct ChordedHoldTests {
    /// The QMK row shows every held modifier, not just the keycode's.
    @Test func qmkExpressionMasksEveryHeldModifier() {
        let held = { (mods: Modifiers) in Key(tap: .code("KC_A"), hold: .code("KC_LEFT_CTRL", modifiers: mods)) }
        #expect(Legends.qmkExpression(for: held([.leftShift])) == "MT(MOD_LCTL | MOD_LSFT, KC_A)")
        #expect(Legends.qmkExpression(for: held([.leftShift, .leftOption, .leftCommand])) == "ALL_T(KC_A)")
        #expect(Legends.qmkExpression(for: held([.leftShift, .leftOption])) == "MEH_T(KC_A)")
    }
}
