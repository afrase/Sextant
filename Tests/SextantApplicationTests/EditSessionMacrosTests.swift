import Foundation
import SextantApplication
import SextantDomain
import Testing

/// Macro edits (spec §6.3): one named undo step each, which brings the selected macro and step back.
@MainActor
struct EditSessionMacrosTests {
    let store = InMemoryLibrary()

    func open(_ file: String = "voyager-XlrR4.json") async throws -> (EditSession, UndoManager) {
        let library = Library(store: store)
        let entry = try await library.importOryxJSON(Fixtures.data(file))
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

    @Test(.enabled(if: Fixtures.reference != nil, "needs SEXTANT_REFERENCE"))
    func everyEditIsOneNamedUndoStep() async throws {
        let (session, undo) = try await open()
        let original = session.layout
        let first = try #require(session.layout.macros.first?.locator)
        let edits: [(String, () -> Void)] = [
            ("New Macro", { session.newMacro() }),
            ("Rename Macro", { session.renameMacro(first, to: "  Arrow  ") }),
            ("Add Step", { session.insertStep(MacroStep(code: "KC_A"), at: 1, in: first) }),
            ("Duplicate Step", { session.duplicateStep(at: 1, in: first) }),
            ("Move Step", { session.moveStep(from: 0, to: 3, in: first) }),
            ("Set Step Key", { session.setStepCode("KC_B", at: 0, in: first) }),
            ("Change Modifiers", { session.setStepModifiers([.leftShift], at: 0, in: first) }),
            ("Set Wait", { session.setStepDelay(250, at: 0, in: first) }),
            ("End with Return", { session.setEndsWithEnter(true, in: first) }),
            ("Hold Option While Typing", { session.setHoldsOption(true, in: first) }),
            ("Delete Step", { session.deleteStep(at: 0, in: first) }),
            ("Record Step", { session.recordStep(MacroStep(code: "KC_C"), pause: 120, at: 2, in: first) }),
        ]
        for (name, edit) in edits {
            step(undo, edit)
            #expect(undo.undoActionName == name)
        }
        let macro = try #require(session.layout.macro(at: first))
        #expect(macro.name == "Arrow" && macro.endsWithEnter && macro.holdsOption)
        #expect(macro.steps[1].delay == 120 && macro.steps[2].code == "KC_C", "a recorded pause is the wait before the new step")
        #expect(session.selection.macro == first && session.selection.step == 2)
        while undo.canUndo { undo.undo() }
        #expect(session.layout == original)
    }

    @Test func assignMovesADraftAndSelectsItOnTheKey() async throws {
        let (session, undo) = try await open("my-layout-KlgM7-40xJ7M.json")
        step(undo) { session.newMacro() }
        let draft = try #require(session.selection.macro)
        step(undo) { session.insertStep(MacroStep(code: "KC_K"), at: 0, in: draft) }
        session.select(layer: 1)
        step(undo) { session.assignMacro(draft, layer: 1, index: 19) }
        #expect(undo.undoActionName == "Assign Macro to Key")
        let placed = MacroLocator.key(KeyRef(layer: 1, index: 19, slot: .tap))
        #expect(session.selection.macro == placed && session.layout.macroDrafts.isEmpty)
        #expect(session.selectedMacro?.steps == [MacroStep(code: "KC_K")])

        step(undo) { session.unassignMacro(placed) }
        #expect(undo.undoActionName == "Remove Macro from Key")
        #expect(session.layout.macroDrafts.count == 1 && session.selection.macro == .draft(session.layout.macroDrafts[0].id))
        undo.undo()
        #expect(session.selection.macro == placed, "undo brings the selection back with the macro")
        undo.undo()
        #expect(session.selection.macro == draft && session.selectedMacro != nil)
    }

    @Test(.enabled(if: Fixtures.reference != nil, "needs SEXTANT_REFERENCE"))
    func deletingTheSelectedMacroClearsTheSelection() async throws {
        let (session, undo) = try await open()
        let first = try #require(session.layout.macros.first?.locator)
        session.selectMacro(first, step: 1)
        step(undo) { session.deleteMacro(first) }
        #expect(undo.undoActionName == "Delete Macro")
        #expect(session.selection.macro == nil && session.selection.step == nil)
        #expect(session.layout.macros.count == 5)
        undo.undo()
        #expect(session.selection.macro == first && session.selection.step == 1)
    }

    /// The selection names a key macro by position: layer edits carry it along, so it never lands on another macro.
    @Test(.enabled(if: Fixtures.reference != nil, "needs SEXTANT_REFERENCE"))
    func theSelectedMacroFollowsItsLayer() async throws {
        let (session, undo) = try await open("voyager-JRGQm.json")
        let teamsCam = MacroLocator.key(KeyRef(layer: 2, index: 32, slot: .tap))
        let macro = session.layout.macro(at: teamsCam)
        session.selectMacro(teamsCam, step: 1)
        step(undo) { session.deleteLayer(1) }
        #expect(session.selection.macro == .key(KeyRef(layer: 1, index: 32, slot: .tap)) && session.selectedMacro == macro)
        step(undo) { session.moveLayer(from: 1, to: 3) }
        #expect(session.selection.macro == .key(KeyRef(layer: 3, index: 32, slot: .tap)) && session.selectedMacro == macro)
        step(undo) { session.deleteLayer(3) }
        #expect(session.selection.macro == nil, "its layer went")
        undo.undo()
        undo.undo()
        #expect(session.selection.macro == .key(KeyRef(layer: 1, index: 32, slot: .tap)), "undo brings it back")
    }

    @Test(.enabled(if: Fixtures.reference != nil, "needs SEXTANT_REFERENCE"))
    func deletingAStepSelectsTheOneTakingItsPlace() async throws {
        let (session, undo) = try await open()
        let first = try #require(session.layout.macros.first?.locator)
        let count = try #require(session.selectedMacro ?? session.layout.macro(at: first)).steps.count
        step(undo) { session.deleteStep(at: count - 1, in: first) }
        #expect(session.selection.step == count - 2, "the last step goes: the one before it")
        step(undo) { session.deleteStep(at: 0, in: first) }
        #expect(session.selection.step == 0)
        session.deleteStep(at: 99, in: first)
        #expect(session.layout.macro(at: first)?.steps.count == count - 2)
    }
}
