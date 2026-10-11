import SextantDomain
import Testing

struct KindAndLegendTests {
    let layout: KeyboardLayout

    init() throws { layout = try Fixtures.layout() }

    @Test func classifiesMainLayerKinds() {
        let keys = layout.layers[0].keys
        let expected: [Int: KeyKind] = [
            0: .dualFunction, 1: .regular, 12: .modifier, 18: .modifier, 19: .dualFunction, 24: .dualFunction, 25: .modifier,
            43: .dualFunction, 51: .dualFunction,
        ]
        for (i, kind) in expected { #expect(keys[i].kind == kind, "key \(i)") }
    }

    @Test func classifiesBrdSysKinds() {
        let keys = layout.layers[2].keys
        #expect(keys[0].kind == .lighting)
        #expect(keys[21].kind == .lighting)
        #expect(keys[44].kind == .label)
        #expect(keys[31].kind == .regular)
        #expect(keys[18].kind == .transparent)
    }

    private func show(_ l: Int, _ i: Int) -> String {
        let r = Legends.legend(layout: layout, layer: l, index: i)
        let p = r.legend.primary.map { $0.text + ($0.side.map { $0 == .left ? "(L)" : "(R)" } ?? "") } ?? "–"
        let s = r.legend.secondary.map { " / " + $0.text + ($0.side.map { $0 == .left ? "(L)" : "(R)" } ?? "") } ?? ""
        return p + s + (r.isInherited ? " [inherited]" : "")
    }

    @Test func legendsMatchOryx() {
        #expect(show(0, 0) == "= / ⎋")
        #expect(show(0, 19) == "Z / ⌥(L)")
        #expect(show(0, 43) == "' / ⇧(R)")
        #expect(show(0, 24) == "⏎ / Sym+Num")
        #expect(show(0, 51) == "␣ / Brd+Sys")
        #expect(show(0, 18) == "⌃(L)")
        #expect(show(0, 25) == "⌘(L)")
        #expect(show(0, 49) == "⌃(R)")
        #expect(show(2, 26) == "6 [inherited]", "Brd+Sys inherits from Main, not Sym+Num")
        #expect(show(2, 18) == "⌃(L) [inherited]")
        #expect(show(2, 44) == "Back")
        #expect(show(2, 31) == "Reset")
        #expect(Legends.legend(for: layout.layers[2].keys[45]).annotation == "⇧⌘[")
    }

    @Test func qmkExpressions() {
        #expect(Legends.legend(for: layout.layers[0].keys[24]).qmk == "LT(1, KC_ENTER)")
        #expect(Legends.legend(for: layout.layers[0].keys[19]).qmk == "MT(MOD_LALT, KC_Z)")
        #expect(Legends.legend(layout: layout, layer: 2, index: 51).activatesDisplayedLayer)
    }

    @Test func transparentResolutionAndOverride() {
        let r = layout.resolvedKey(layer: 1, index: 19)
        #expect(r.isInherited)
        #expect(r.sourceLayer == 0)
        #expect(r.effective.tap?.code == "KC_Z")
    }

    @Test func movingLayersRemapsReferences() {
        var l = layout
        l.layers.append(.transparent(title: "Games"))
        l.moveLayer(from: 1, to: 3)
        #expect(l.layerNames == ["Main", "Brd+Sys", "Games", "Sym+Num"])
        #expect(l.key(layer: 0, index: 24)?.hold?.layer == 3)
        #expect(l.key(layer: 0, index: 51)?.hold?.layer == 1)
        l.removeLayer(at: 3)
        #expect(l.key(layer: 0, index: 24)?.hold?.isNone == true, "references to a deleted layer become KC_NO")
    }

    @Test func layerChangesReachCombosAndNavigatorOptions() {
        var l = layout
        l.layers.append(.transparent(title: "Games"))
        l.combos = [
            Combo(id: "a", keyIndices: [13, 14], layer: 1, output: .code("KC_ESCAPE")),
            Combo(id: "b", keyIndices: [15, 16], layer: 3, output: .code("KC_TAB")),
        ]
        l.navigator = NavigatorConfig(kind: .trackpad, side: .right, options: ["aimLayers": .integers([1, 3])])
        l.automouseLayer = 1
        l.removeLayer(at: 1)
        #expect(l.combos.map(\.id) == ["b"], "a combo limited to the deleted layer goes with it")
        #expect(l.combos.first?.layer == 2, "combos above it shift down")
        #expect(l.navigator?.options["aimLayers"] == .integers([2]))
        #expect(l.automouseLayer == nil)
    }

    @Test func diffFindsChangedKeys() {
        var edited = layout
        edited.updateKey(layer: 2, index: 45) { $0.customLabel = "Prev" }
        edited.updateKey(layer: 0, index: 1) { $0 = Key("KC_Q") }
        let diff = edited.diff(from: layout)
        #expect(diff.keyChanges.map(\.index).sorted() == [1, 45])
        #expect(diff.keyChanges.first { $0.index == 45 }?.labelChanged == true)
    }
}
