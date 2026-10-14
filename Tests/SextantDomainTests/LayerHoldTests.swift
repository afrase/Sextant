import Foundation
import Testing

@testable import SextantDomain

/// Telling a held layer from a locked one (ADR 0050). `pressed` maps each key held down to the layer it went down on.
struct LayerHoldTests {
    /// The user's layout: Main's ⏎ (key 24) holds Sym+Num and Space (key 51) holds Brd+Sys.
    @Test func theUsersThumbKeysHoldTheirLayers() throws {
        let layout = try Fixtures.layout()
        #expect(LayerHold.classify(layout: layout, layer: 0, pressed: [24: 0]) == .base)
        #expect(LayerHold.classify(layout: layout, layer: 1, pressed: [24: 0]) == .momentary(heldBy: 24))
        #expect(LayerHold.classify(layout: layout, layer: 2, pressed: [51: 0, 13: 2]) == .momentary(heldBy: 51))
        #expect(LayerHold.classify(layout: layout, layer: 1, pressed: [51: 0]) == .locked, "Space holds Brd+Sys, not Sym+Num")
        #expect(LayerHold.classify(layout: layout, layer: 1, pressed: [:]) == .locked, "nothing held: a host move, say")
        // On Sym+Num the thumb key is transparent, so it acts as Main's: still the holder.
        #expect(LayerHold.classify(layout: layout, layer: 1, pressed: [24: 1]) == .momentary(heldBy: 24))
    }

    @Test func eachLayerFunctionIsHeldOrLocked() {
        let layout = synthetic([
            0: Key(tap: .code("KC_SPACE"), hold: .momentary(3)),  // LT(3, Space)
            1: Key(tap: .toggle(3)),
            2: Key(tap: .moveTo(3)),
            3: Key(tap: KeyAction(code: "TT", layer: 3)),
            4: Key(tap: KeyAction(code: "LM", layer: 3, modifiers: .leftShift)),
            5: Key(tap: .oneShotLayer(3)),
            6: Key(tap: KeyAction(code: "DF", layer: 3)),
            7: Key(tap: .code("KC_A"), doubleTap: .moveTo(3), tapHold: .momentary(3)),  // a tap dance
            8: Key(tap: .code("KC_A"), hold: .moveTo(3)),  // a dual function that goes to the layer
        ])
        func hold(_ index: Int) -> LayerHold { LayerHold.classify(layout: layout, layer: 3, pressed: [index: 0]) }
        #expect(hold(0) == .momentary(heldBy: 0))
        #expect(hold(1) == .locked)
        #expect(hold(2) == .locked)
        #expect(hold(3) == .momentary(heldBy: 3), "a TT held down")
        #expect(hold(4) == .momentary(heldBy: 4))
        #expect(hold(5) == .momentary(heldBy: 5), "an OSL held down")
        #expect(hold(6) == .locked)
        #expect(hold(7) == .momentary(heldBy: 7), "the dance's tap-then-hold holds the layer")
        #expect(hold(8) == .locked)
        #expect(LayerHold.classify(layout: layout, layer: 3, pressed: [3: 0, 0: 0]) == .momentary(heldBy: 0), "lowest index wins")
        #expect(LayerHold.classify(layout: layout, layer: 3, pressed: [:]) == .locked, "a tapped TT, once let go")
    }

    /// The firmware picks a key's action on the layer that was on when it went down, not the layer on now.
    @Test func aKeyActsAsOnTheLayerItWentDownOn() {
        var layout = synthetic([24: Key(tap: .code("KC_ENTER"), hold: .momentary(1))])
        layout.layers[1].keys[30] = Key(tap: .code("KC_A"), hold: .momentary(2))
        layout.layers[2].keys[24] = Key("KC_B")
        #expect(LayerHold.classify(layout: layout, layer: 2, pressed: [24: 0, 30: 1]) == .momentary(heldBy: 30))
        #expect(LayerHold.classify(layout: layout, layer: 1, pressed: [24: 0]) == .momentary(heldBy: 24))
        #expect(LayerHold.classify(layout: layout, layer: 1, pressed: [24: 2]) == .locked, "on Brd+Sys the key types B")
        #expect(LayerHold.classify(layout: layout, layer: 2, pressed: [30: 0]) == .locked, "key 30 does nothing on Main")
    }

    @Test func theNavigatorsAutoMouseLayerIsThePointers() {
        var layout = synthetic([:])
        layout.automouseLayer = 3
        #expect(LayerHold.classify(layout: layout, layer: 3, pressed: [:]) == .locked, "no Navigator, no auto-mouse")
        layout.navigator = NavigatorConfig(kind: .trackpad, side: .right)
        #expect(LayerHold.classify(layout: layout, layer: 3, pressed: [:]) == .pointer)
        layout.layers[0].keys[0] = Key(tap: .momentary(3))
        #expect(LayerHold.classify(layout: layout, layer: 3, pressed: [0: 0]) == .momentary(heldBy: 0), "a key holding it wins")
    }

    // Other people's layouts, from the reference folder.

    @Test(.enabled(if: Fixtures.reference != nil, "needs SEXTANT_REFERENCE"))
    func xlrR4TapsToLayer4() throws {
        let layout = try Fixtures.layout("voyager-XlrR4.json")
        #expect(LayerHold.classify(layout: layout, layer: 4, pressed: [0: 1]) == .locked, "layer 1's key 0 is TO(4)")
        #expect(LayerHold.classify(layout: layout, layer: 2, pressed: [42: 0]) == .momentary(heldBy: 42))
    }

    @Test(.enabled(if: Fixtures.reference != nil, "needs SEXTANT_REFERENCE"))
    func jrgqmHoldsToAndTapToggles() throws {
        let layout = try Fixtures.layout("voyager-JRGQm.json")
        #expect(LayerHold.classify(layout: layout, layer: 11, pressed: [0: 0]) == .locked, "key 0's hold is TO(11)")
        #expect(LayerHold.classify(layout: layout, layer: 7, pressed: [8: 6]) == .momentary(heldBy: 8), "TT(7) held")
        // Mouse is also the Navigator's auto-mouse layer, so a tapped TT(7) reads as the pointer moving.
        #expect(LayerHold.classify(layout: layout, layer: 7, pressed: [:]) == .pointer)
        #expect(LayerHold.classify(layout: layout, layer: 6, pressed: [:]) == .locked, "Scroll with nothing held")
        #expect(LayerHold.classify(layout: layout, layer: 8, pressed: [42: 0, 50: 2, 25: 3]) == .momentary(heldBy: 25))
    }

    @Test(.enabled(if: Fixtures.reference != nil, "needs SEXTANT_REFERENCE"))
    func e5RrrDoubleTapsTo() throws {
        let layout = try Fixtures.layout("voyager-e5Rrr.json")
        #expect(LayerHold.classify(layout: layout, layer: 1, pressed: [49: 0]) == .locked, "key 49's double tap is TO(1)")
        #expect(LayerHold.classify(layout: layout, layer: 1, pressed: [:]) == .locked)
    }

    @Test(.enabled(if: Fixtures.reference != nil, "needs SEXTANT_REFERENCE"))
    func m9dpxHoldsAOneShotLayer() throws {
        let layout = try Fixtures.layout("voyager-m9dpx.json")
        #expect(LayerHold.classify(layout: layout, layer: 5, pressed: [40: 4]) == .momentary(heldBy: 40), "OSL(5) held")
        #expect(LayerHold.classify(layout: layout, layer: 5, pressed: [:]) == .locked, "the one-shot, once let go")
    }

    /// Four transparent layers with `base`'s keys on Main.
    private func synthetic(_ base: [Int: Key]) -> KeyboardLayout {
        var layout = KeyboardLayout(title: "Synthetic", layers: (0..<4).map { Layer.transparent(title: "L\($0)") })
        layout.layers[0].keys = (0..<52).map { base[$0] ?? Key("KC_A") }
        return layout
    }
}
