import Foundation
import SextantApplication
import SextantDomain
import Testing

/// Combo edits (spec §6.4, ADR 0046): one named undo step each, which brings the selected combo back.
@MainActor
struct EditSessionCombosTests {
    func open() async throws -> (EditSession, UndoManager) {
        let library = Library(store: InMemoryLibrary())
        let entry = try await library.importOryxJSON(Fixtures.userLayoutData)
        let session = try await library.open(entry.id, autosaveDelay: .milliseconds(1))
        let undo = UndoManager()
        undo.groupsByEvent = false
        session.undoManager = undo
        return (session, undo)
    }

    func step(_ undo: UndoManager, _ body: () -> Void) {
        undo.beginUndoGrouping()
        body()
        undo.endUndoGrouping()
    }

    @Test func everyEditIsOneNamedUndoStep() async throws {
        let (session, undo) = try await open()
        let original = session.layout
        var id = ""
        step(undo) { id = session.newCombo(keys: [39, 40], layer: 0, output: .code("KC_ESCAPE")) }
        #expect(
            undo.undoActionName == "New Combo" && session.selection.combo == id && session.layout.combo(id: id)?.keyIndices == [39, 40])
        let edits: [(String, () -> Void)] = [
            ("Change Combo Keys", { session.toggleComboKey(41, in: id) }),
            ("Change Combo Keys", { session.setComboKeys([38, 39], in: id) }),
            ("Set Combo Output", { session.setComboOutput(.code("KC_TAB"), in: id) }),
            ("Change Combo Layer", { session.setComboLayer(1, in: id) }),
        ]
        for (name, edit) in edits {
            session.selectCombo(nil)
            step(undo, edit)
            #expect(undo.undoActionName == name)
            #expect(session.selection.combo == id, "\(name) selects its combo")
        }
        // The name field commits when the user has moved on to another combo: the rename leaves that choice alone.
        session.selectCombo(nil)
        step(undo) { session.renameCombo(id, to: "Tab") }
        #expect(undo.undoActionName == "Rename Combo" && session.selection.combo == nil)
        session.selectCombo(id)
        let combo = try #require(session.layout.combo(id: id))
        #expect(combo.keyIndices == [38, 39] && combo.output == .code("KC_TAB") && combo.layer == 1 && combo.name == "Tab")
        step(undo) { session.deleteCombo(id) }
        #expect(undo.undoActionName == "Delete Combo" && session.layout.combos.isEmpty && session.selection.combo == nil)
        undo.undo()
        #expect(session.selection.combo == id && session.layout.combo(id: id)?.name == "Tab", "undo brings the selection back")
        while undo.canUndo { undo.undo() }
        #expect(session.layout == original)
    }

    /// Delete Layer takes the combos reading it, and with them a selection that would point at nothing.
    @Test func deletingTheLayerAComboReadsClearsItsSelection() async throws {
        let (session, undo) = try await open()
        var id = ""
        step(undo) { id = session.newCombo(keys: [39, 40], layer: 2, output: .code("KC_ESCAPE")) }
        step(undo) { session.deleteLayer(2) }
        #expect(session.layout.combos.isEmpty && session.selection.combo == nil)
        undo.undo()
        #expect(session.selection.combo == id)
    }
}
