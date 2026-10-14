import Foundation
import SextantApplication
import SextantDomain
import Testing

@testable import SextantBuild

/// Combos made in Sextant build as Oryx's do: the keycodes at their keys on the layer they read, in `COMBO()` lines and
/// `COMBO_COUNT`. Keys a combo can't match are refused on their key, as the live issues say (ADR 0046).
struct ComboGeneratorTests {
    let identity = FirmwareIdentity(serial: "KlgM7/40xJ7M")

    func layout() throws -> KeyboardLayout {
        try KeyboardLayout(oryxJSON: Data(contentsOf: QMKGeneratorGoldenTests.example("my-layout-KlgM7-40xJ7M.json")))
    }

    @Test func aComboMadeInSextantEmitsComboAndCount() throws {
        var layout = try layout()
        layout.addCombo(Combo(keyIndices: [39, 40], layer: 0, output: .code("KC_ESCAPE")))
        layout.addCombo(Combo(name: "Paren", keyIndices: [38, 39, 40], layer: 1, output: .code("KC_LPRN")))
        layout.addCombo(Combo(keyIndices: [13, 14], output: .momentary(2)))
        let files = try QMKGenerator().generate(layout, identity: identity).files
        let keymap = try #require(files["keymap.c"])
        #expect(keymap.contains("const uint16_t PROGMEM combo0[] = { KC_J, KC_K, COMBO_END};"))
        #expect(keymap.contains("const uint16_t PROGMEM combo1[] = { KC_4, KC_5, KC_6, COMBO_END};"), "Sym+Num's keys")
        #expect(keymap.contains("const uint16_t PROGMEM combo2[] = { KC_A, KC_S, COMBO_END};"), "no layer reads the base layer")
        #expect(
            keymap.contains("COMBO(combo0, KC_ESCAPE),") && keymap.contains("COMBO(combo1, KC_LPRN),")
                && keymap.contains("COMBO(combo2, MO(2)),"))
        #expect(files["config.h"]?.contains("#define COMBO_COUNT 3") == true)
        #expect(files["rules.mk"]?.contains("COMBO_ENABLE = yes") == true)
    }

    @Test func refusesKeysAComboCantMatch() throws {
        var layout = try layout()
        // Sym+Num's 12 is transparent.
        layout.combos = [Combo(keyIndices: [13, 12], layer: 1, output: .code("KC_A"))]
        #expect(throws: GeneratorError.unsupported("a combo key that is transparent", KeyRef(layer: 1, index: 12))) {
            try QMKGenerator().generate(layout, identity: identity)
        }
        layout.updateKey(layer: 0, index: 13) { $0 = Key(tap: .code("KC_A"), doubleTap: .code("KC_B")) }
        layout.combos = [Combo(keyIndices: [14, 13], layer: 0, output: .code("KC_A"))]
        #expect(throws: GeneratorError.unsupported("a combo key that is a tap dance", KeyRef(layer: 0, index: 13))) {
            try QMKGenerator().generate(layout, identity: identity)
        }
        // KC_NO is COMBO_END: the list would stop at it.
        layout.updateKey(layer: 0, index: 13) { $0 = .none }
        #expect(throws: GeneratorError.unsupported("a combo key that is disabled", KeyRef(layer: 0, index: 13))) {
            try QMKGenerator().generate(layout, identity: identity)
        }
    }
}
