import Foundation
import Testing

@testable import SextantDomain

/// Combo edits and checks (spec §6.4, §7.5, ADR 0046), on the user's layout (Main: J is key 39, K 40, L 41).
struct ComboTests {
    func layout(_ combos: Combo...) throws -> KeyboardLayout {
        var layout = try Fixtures.layout()
        layout.combos = combos
        return layout
    }

    func kinds(_ layout: KeyboardLayout, _ id: String) -> [LayoutIssue.Kind] {
        LayoutIssues.check(layout).filter { $0.combo == id }.map(\.kind)
    }

    @Test func editsChangeOnlyTheirCombo() throws {
        var layout = try self.layout(Combo(id: "a", keyIndices: [39, 40], layer: 0, output: .code("KC_ESCAPE")))
        layout.addCombo(Combo(id: "b", keyIndices: [13, 14], output: .code("KC_TAB")))
        layout.toggleComboKey(41, in: "a")
        #expect(layout.combo(id: "a")?.keyIndices == [39, 40, 41])
        layout.toggleComboKey(40, in: "a")
        #expect(layout.combo(id: "a")?.keyIndices == [39, 41], "a key already in comes out")
        layout.toggleComboKey(99, in: "a")
        #expect(layout.combo(id: "a")?.keyIndices == [39, 41], "a key off the board is refused")
        layout.setComboKeys([1, 2, 3, 4, 5, 6], in: "a")
        layout.toggleComboKey(7, in: "a")
        #expect(layout.combo(id: "a")?.keyIndices == [1, 2, 3, 4, 5, 6], "a seventh key is refused")
        layout.setComboKeys([3, 3, 60, 2], in: "a")
        #expect(layout.combo(id: "a")?.keyIndices == [3, 2], "repeats and keys off the board are dropped")
        layout.setComboOutput(.momentary(1), in: "a")
        layout.setComboLayer(2, in: "a")
        layout.setComboLayer(9, in: "a")
        layout.renameCombo(id: "a", to: "  Arrows ")
        let a = try #require(layout.combo(id: "a"))
        #expect(a.output == .momentary(1) && a.layer == 2 && a.name == "Arrows", "a layer that doesn't exist is ignored")
        layout.renameCombo(id: "a", to: " ")
        #expect(layout.combo(id: "a")?.name == nil)
        layout.removeCombo(id: "a")
        #expect(layout.combos.map(\.id) == ["b"] && layout.combo(id: "b")?.keysLayer == 0, "no layer reads the base layer")
        let before = layout
        layout.toggleComboKey(1, in: "gone")
        layout.renameCombo(id: "gone", to: "x")
        #expect(layout == before, "an id the layout lacks changes nothing")
    }

    @Test func tooManyKeysDuplicatesAndBadKeysAreErrors() throws {
        var layout = try self.layout(
            Combo(id: "seven", keyIndices: [1, 2, 3, 4, 5, 7, 8], layer: 0, output: .code("KC_A")),
            Combo(id: "jk", keyIndices: [39, 40], layer: 0, output: .code("KC_ESCAPE")),
            Combo(id: "kj", keyIndices: [40, 39], output: .code("KC_TAB")),
            Combo(id: "jk on Sym+Num", keyIndices: [39, 40], layer: 1, output: .code("KC_TAB")),
            // Sym+Num's 12 and 24 are transparent; Main's 24 is a layer-tap, not a tap dance.
            Combo(id: "see-through", keyIndices: [12, 24], layer: 1, output: .code("KC_B")),
            Combo(id: "one", keyIndices: [3], output: .code("KC_C")))
        layout.updateKey(layer: 0, index: 13) { $0 = Key(tap: .code("KC_A"), doubleTap: .code("KC_B")) }
        layout.addCombo(Combo(id: "dance", keyIndices: [13, 21], output: .code("KC_D")))

        #expect(kinds(layout, "seven") == [.comboTooManyKeys(7)])
        #expect(kinds(layout, "jk").contains(.duplicateComboTrigger) && kinds(layout, "kj").contains(.duplicateComboTrigger))
        #expect(!kinds(layout, "jk on Sym+Num").contains(.duplicateComboTrigger), "another layer's keys aren't the same trigger")
        #expect(kinds(layout, "see-through") == [.comboKeyTransparent(12), .comboKeyTransparent(24)])
        #expect(kinds(layout, "dance") == [.comboKeyTapDance(13)])
        #expect(kinds(layout, "one") == [.emptyCombo], "fewer than 2 keys is an empty combo, never two errors")
        let others = LayoutIssues.check(layout).filter { issue in
            if case .rollingNeighbors = issue.kind { false } else { issue.combo != nil }
        }
        #expect(others.allSatisfy { $0.severity == .error }, "only rolling neighbors is a warning")
    }

    @Test func keysSideBySideInARowAreRollingNeighbors() throws {
        let layout = try self.layout(
            Combo(id: "jk", keyIndices: [40, 39], output: .code("KC_ESCAPE")),
            Combo(id: "sdf", keyIndices: [16, 14, 15], output: .code("KC_TAB")),
            Combo(id: "gap", keyIndices: [13, 15], output: .code("KC_A")),
            Combo(id: "rows", keyIndices: [14, 8], output: .code("KC_B")),
            Combo(id: "halves", keyIndices: [17, 38], output: .code("KC_C")),
            Combo(id: "right thumbs", keyIndices: [50, 51], output: .code("KC_D")))
        let rolling = LayoutIssues.check(layout).filter { if case .rollingNeighbors = $0.kind { true } else { false } }
        #expect(rolling.allSatisfy { $0.severity == .warning })
        #expect(kinds(layout, "jk") == [.rollingNeighbors(39, 40)], "named left to right")
        #expect(kinds(layout, "sdf") == [.rollingNeighbors(14, 15)], "one roll across all three")
        #expect(kinds(layout, "gap").isEmpty && kinds(layout, "rows").isEmpty && kinds(layout, "halves").isEmpty)
        #expect(kinds(layout, "right thumbs") == [.rollingNeighbors(50, 51)], "the inner thumb is left of the outer one")
    }

    /// Deleting a layer takes the combos that read it, and the rest follow their layer (ADR 0037).
    @Test func deletingALayerRemapsCombos() throws {
        var layout = try self.layout(
            Combo(id: "main", keyIndices: [39, 40], layer: 0, output: .momentary(2)),
            Combo(id: "sym", keyIndices: [39, 40], layer: 1, output: .code("KC_A")),
            Combo(id: "brd", keyIndices: [39, 40], layer: 2, output: .code("KC_B")))
        layout.removeLayer(at: 1)
        #expect(layout.combos.map(\.id) == ["main", "brd"])
        #expect(layout.combo(id: "brd")?.layer == 1 && layout.combo(id: "main")?.output == .momentary(1))
        layout.removeLayer(at: 1)
        #expect(
            layout.combos.map(\.id) == ["main"] && layout.combo(id: "main")?.output == KeyAction.none,
            "a layer key to a deleted layer does nothing")
    }

    /// Other people's samples import without combo errors: their combos build in Oryx.
    @Test(.enabled(if: Fixtures.reference != nil, "needs SEXTANT_REFERENCE"))
    func referenceCombosHaveNoErrors() throws {
        for file in ["voyager-JRGQm.json", "voyager-m9dpx.json"] {
            let layout = try Fixtures.layout(file)
            let errors = LayoutIssues.check(layout).filter { $0.combo != nil && $0.severity == .error }
            #expect(errors.isEmpty, "\(file): \(errors)")
        }
        #expect(try Fixtures.layout("voyager-JRGQm.json").combos.count == 32)
    }
}
