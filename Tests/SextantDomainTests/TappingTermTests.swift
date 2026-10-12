import Foundation
import SextantDomain
import Testing

struct TappingTermTests {
    /// Two layers with the same layer-tap key on both, and a different one beside it.
    func layout() -> KeyboardLayout {
        var layout = KeyboardLayout(title: "Test", layers: [.transparent(title: "Base"), .transparent(title: "One")])
        let layerTap = Key(tap: .code("KC_SPACE"), hold: .momentary(1))
        layout.updateKey(layer: 0, index: 51) { $0 = layerTap }
        layout.updateKey(layer: 1, index: 51) { $0 = Key(tap: layerTap.tap, hold: layerTap.hold, customLabel: "Space") }
        layout.updateKey(layer: 0, index: 50) { $0 = Key(tap: .code("KC_SPACE"), hold: .momentary(1), doubleTap: .code("KC_A")) }
        return layout
    }

    /// QMK looks terms up by keycode: keys with the same actions share the term; others keep theirs.
    @Test func setsTheTermOnKeysWithTheSameActions() {
        var layout = layout()
        layout.setTappingTerm(240, layer: 0, index: 51)
        #expect(layout.key(layer: 0, index: 51)?.tappingTerm == 240)
        #expect(layout.key(layer: 1, index: 51)?.tappingTerm == 240, "a label doesn't change the keycode")
        #expect(layout.key(layer: 0, index: 50)?.tappingTerm == nil)
        layout.setTappingTerm(nil, layer: 1, index: 51)
        #expect(layout.key(layer: 0, index: 51)?.tappingTerm == nil && layout.key(layer: 1, index: 51)?.tappingTerm == nil)
    }

    /// Oryx stores the global term as nil; the generator accepts 0...1000.
    @Test func storesTheGlobalTermAsNilAndBoundsTheRest() {
        var layout = layout()
        #expect(layout.globalTappingTerm == 200)
        layout.setTappingTerm(200, layer: 0, index: 50)
        #expect(layout.key(layer: 0, index: 50)?.tappingTerm == nil)
        layout.setTappingTerm(5000, layer: 0, index: 50)
        #expect(layout.key(layer: 0, index: 50)?.tappingTerm == 1000)
        layout.setTappingTerm(-10, layer: 0, index: 50)
        #expect(layout.key(layer: 0, index: 50)?.tappingTerm == 0)
        layout.settings["tappingTerm"] = .number(180)
        #expect(layout.globalTappingTerm == 180)
        layout.setTappingTerm(180, layer: 0, index: 50)
        #expect(layout.key(layer: 0, index: 50)?.tappingTerm == nil)
        layout.setTappingTerm(200, layer: 0, index: 50)
        #expect(layout.key(layer: 0, index: 50)?.tappingTerm == 200)
    }

    /// The term times holds and dances, read from the slots: a label or macro changes the kind, not the timing.
    @Test func keysWithAHoldOrDanceUseTheTerm() {
        let macro = KeyAction(code: "KC_TRANSPARENT", macro: Macro(steps: [MacroStep(code: "KC_A")]))
        #expect(Key(tap: .code("KC_A"), hold: .momentary(1)).usesTappingTerm)
        #expect(Key(tap: .code("KC_A"), hold: .code("KC_LEFT_ALT"), customLabel: "A").usesTappingTerm)
        #expect(Key(tap: macro, doubleTap: .code("KC_B")).usesTappingTerm)
        #expect(Key(tapHold: .code("KC_LEFT_CTRL")).usesTappingTerm)
        #expect(!Key("KC_A").usesTappingTerm)
        #expect(!Key(tap: macro).usesTappingTerm)
        #expect(!Key(tap: .momentary(1)).usesTappingTerm)
    }
}
