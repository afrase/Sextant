import Foundation
import SextantApplication
import SextantDomain
import Testing

@MainActor
struct EditSessionTests {
    let store = InMemoryLibrary()

    func open() async throws -> (EditSession, UndoManager) {
        let library = Library(store: store)
        let entry = try await library.importOryxJSON(Fixtures.userLayoutData)
        let session = try await library.open(entry.id, autosaveDelay: .milliseconds(1))
        let undo = UndoManager()
        undo.groupsByEvent = false
        session.undoManager = undo
        return (session, undo)
    }

    /// Each edit is its own undo group, as each user action is in the app.
    func step(_ undo: UndoManager, _ body: () -> Void) {
        undo.beginUndoGrouping()
        body()
        undo.endUndoGrouping()
    }

    @Test func undoAndRedoRestoreLayoutAndSelection() async throws {
        let (session, undo) = try await open()
        let original = session.layout
        session.select(key: 13)
        step(undo) { session.setCode("KC_Q") }
        #expect(session.layout.key(layer: 0, index: 13)?.tap?.code == "KC_Q")
        #expect(undo.undoActionName == "Set Tap")
        step(undo) { session.setHoldLayer(1) }
        #expect(session.layout.key(layer: 0, index: 13)?.kind == .dualFunction)
        session.select(key: 40)
        undo.undo()
        #expect(session.selection.keyIndex == 13, "undo restores the selection")
        undo.undo()
        #expect(session.layout == original)
        undo.redo()
        #expect(session.layout.key(layer: 0, index: 13)?.tap?.code == "KC_Q")
        #expect(session.canUndo && session.canRedo)
    }

    @Test func layerEditsKeepReferencesAndSelection() async throws {
        let (session, undo) = try await open()
        step(undo) { session.addLayer(title: "Games") }
        #expect(session.selection.layer == 3)
        session.select(layer: 1)
        step(undo) { session.moveLayer(from: 1, to: 3) }
        #expect(session.layout.layerNames == ["Main", "Brd+Sys", "Games", "Sym+Num"])
        #expect(session.selection.layer == 3, "the selection follows the moved layer")
        #expect(session.layout.key(layer: 0, index: 24)?.hold?.layer == 3)
        step(undo) { session.renameLayer(3, to: "  ") }
        #expect(session.layout.layers[3].title == "Sym+Num", "blank names are ignored")
    }

    @Test func redoRestoresTheAdjustedSelection() async throws {
        let (session, undo) = try await open()
        session.select(layer: 2)
        step(undo) { session.deleteLayer(2) }
        #expect(session.selection.layer == 1)
        undo.undo()
        #expect(session.selection.layer == 2)
        undo.redo()
        #expect(session.selection.layer == 1, "redo must not restore an out-of-range layer")
        session.select(layer: 1)
        step(undo) { session.deleteLayer(0) }
        #expect(session.selection.layer == 0, "the same layer stays shown when one below it goes")
        #expect(session.currentLayer?.title == "Sym+Num")
    }

    @Test func overrideCopiesTheInheritedKey() async throws {
        let (session, _) = try await open()
        session.select(layer: 1)
        session.select(key: 19)
        session.overrideInherited()
        #expect(session.layout.key(layer: 1, index: 19)?.tap?.code == "KC_Z")
        #expect(session.layout.key(layer: 1, index: 19)?.hold?.code == "KC_LEFT_ALT")
    }

    @Test func swapAndCopyKeys() async throws {
        let (session, _) = try await open()
        let a = session.layout.key(layer: 0, index: 1), b = session.layout.key(layer: 0, index: 2)
        session.swapKeys(1, 2)
        #expect(session.layout.key(layer: 0, index: 1) == b && session.layout.key(layer: 0, index: 2) == a)
        session.swapKeys(1, 2, copy: true)
        #expect(session.layout.key(layer: 0, index: 2) == b)
    }

    @Test func settingsAreStoredSparsely() async throws {
        let (session, _) = try await open()
        session.setSetting("tappingTerm", to: .number(180))
        #expect(session.layout.settings["tappingTerm"] == .number(180))
        session.setSetting("tappingTerm", to: .number(200))
        #expect(session.layout.settings["tappingTerm"] == nil, "a value equal to the default is removed")
    }

    @Test func autosavesAfterEdits() async throws {
        let (session, _) = try await open()
        session.select(key: 1)
        session.setCode("KC_F1")
        await session.flush()
        #expect(await store.layout(session.id)?.key(layer: 0, index: 1)?.tap?.code == "KC_F1")
        #expect(session.saveError == nil)
    }

    @Test func savesRevisions() async throws {
        let (session, _) = try await open()
        let summary = try await session.saveRevision(source: .save, message: "Tweak")
        #expect(session.revisions.map(\.number) == [1, 2])
        #expect(summary.message == "Tweak")
    }
}
