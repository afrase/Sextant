import Foundation
import SextantDomain
import Testing

/// `KeyboardLayout.changes(from:)`: what History and Save Revision count (ADR 0043).
struct LayoutDiffTests {
    let layout: KeyboardLayout

    init() throws { layout = try Fixtures.layout() }

    @Test func anUnchangedLayoutHasNoChanges() {
        #expect(layout.changes(from: layout).isEmpty)
    }

    @Test func keysAreAddedChangedOrRemovedAndCountedByLayer() throws {
        var edited = layout
        let transparent = try #require(layout.layers[1].keys.firstIndex { $0.isTransparent })
        let own = try #require(layout.layers[1].keys.firstIndex { !$0.isTransparent })
        edited.updateKey(layer: 1, index: transparent) { $0 = Key("KC_F13") }
        edited.updateKey(layer: 1, index: own) { $0 = .transparent }
        edited.updateKey(layer: 2, index: 45) { $0.customLabel = "Prev" }
        let changes = edited.changes(from: layout)
        let kinds = Dictionary(uniqueKeysWithValues: changes.diff.keyChanges.map { (KeyRef(layer: $0.layer, index: $0.index), $0.kind) })
        #expect(kinds[KeyRef(layer: 1, index: transparent)] == .added)
        #expect(kinds[KeyRef(layer: 1, index: own)] == .removed)
        #expect(kinds[KeyRef(layer: 2, index: 45)] == .modified)
        #expect(changes.diff.changes(onLayer: 1).count == 2 && changes.diff.changes(onLayer: 2).count == 1)
        #expect(changes.count == 3)
    }

    @Test func settingsOnlyIsAChange() {
        var edited = layout
        edited.settings["tappingTerm"] = .number(180)
        edited.settings["flowTap"] = .number(100)
        let changes = edited.changes(from: layout)
        #expect(changes.diff.isEmpty && !changes.isEmpty)
        #expect(changes.settings == ["flowTap", "tappingTerm"])
        #expect(changes.count == 2)
    }

    @Test func theNavigatorsOptionsAreSettingsAndItsPlaceIsAFlag() {
        var old = layout
        old.navigator = NavigatorConfig(kind: .trackpad, side: .right)
        var new = old
        new.navigator?.options["scrollInertia"] = .bool(true)
        #expect(new.changes(from: old).settings == ["scrollInertia"] && !new.changes(from: old).navigatorChanged)
        new.navigator?.side = .left
        #expect(new.changes(from: old).navigatorChanged)
        var automouse = old
        automouse.automouseLayer = 2
        #expect(automouse.changes(from: old).navigatorChanged)
    }

    /// Oryx numbers combo ids by position, so deleting the first combo renumbers the rest.
    @Test(.enabled(if: Fixtures.reference != nil, "needs SEXTANT_REFERENCE"))
    func combosAreComparedByContentNotId() throws {
        let m9dpx = try Fixtures.layout("voyager-m9dpx.json")
        var renumbered = m9dpx
        renumbered.combos = m9dpx.combos.reversed().enumerated().map { n, combo in
            var combo = combo
            combo.id = "combo-\(n)"
            return combo
        }
        #expect(renumbered.changes(from: m9dpx).isEmpty, "the same combos under other ids")

        var edited = m9dpx
        edited.combos[0].output = .code("KC_ESCAPE")
        let changes = edited.changes(from: m9dpx)
        #expect(changes.addedCombos == [edited.combos[0]] && changes.removedCombos == [m9dpx.combos[0]])
    }

    @Test func aNewLayersOwnKeysAreAdded() {
        var edited = layout
        var games = Layer.transparent(title: "Games")
        games.keys[3] = Key("KC_W")
        games.keys[4] = Key("KC_A")
        edited.layers.append(games)
        let changes = edited.changes(from: layout)
        #expect(changes.diff.addedLayers.map(\.id) == [games.id])
        #expect(changes.diff.changes(onLayer: 3).map(\.index) == [3, 4])
        #expect(changes.diff.changes(onLayer: 3).allSatisfy { $0.kind == .added && $0.before == nil })
    }

    /// Layers match by id, so one that only moved has no key changes; the move itself counts.
    @Test func aMovedLayerIsMatchedById() {
        var moved = layout
        moved.layers.swapAt(1, 2)
        let changes = moved.changes(from: layout)
        #expect(changes.diff.isEmpty && changes.layersMoved && changes.count == 1)
        var removed = layout
        removed.layers.remove(at: 1)
        #expect(!removed.changes(from: layout).layersMoved, "the layers after a removed one didn't move")
    }

    /// Rename Layout is an edit, so the revision it makes must not read as "no changes".
    @Test func aRenameIsAChange() {
        var renamed = layout
        renamed.title = "Work"
        let changes = renamed.changes(from: layout)
        #expect(changes.titleChanged && changes.count == 1)
    }
}
