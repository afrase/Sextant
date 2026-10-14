import Foundation
import SextantApplication
import SextantDomain
import Testing

@testable import SextantUI

/// The Combos and Macros pages' actions in the Edit menu and ⌘K (spec §9.1, §11): on only on their page with something
/// to act on, and running what the page's own controls run.
@MainActor
struct PageCommandsTests {
    func commandIDs(_ model: LayoutWindowModel, _ query: String) -> Set<String> {
        model.openPalette(query: query)
        defer { model.closePalette() }
        return Set(model.paletteItems.map(\.id).filter { $0.hasPrefix("command-") })
    }

    func run(_ model: LayoutWindowModel, _ title: String) throws {
        model.openPalette(query: title)
        model.run(try #require(model.paletteItems.first { $0.id == "command-\(title)" }, "\(title)"))
    }

    @Test func comboCommandsNeedTheirPageAndACombo() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        #expect(!model.canStartNewCombo && model.comboForKeys == nil, "the Keys page")
        #expect(commandIDs(model, "combo").isDisjoint(with: ["command-New Combo", "command-Edit Combo Keys…", "command-Delete Combo"]))

        model.destination = .combos
        #expect(model.canStartNewCombo && model.comboForKeys == nil, "no combo selected")
        #expect(commandIDs(model, "combo") == ["command-New Combo"])
        let id = session.newCombo(keys: [39, 40], layer: 0, output: .code("KC_ESCAPE"))
        model.selectCombo(id)
        #expect(model.comboForKeys == id)
        #expect(commandIDs(model, "combo").isSuperset(of: ["command-New Combo", "command-Edit Combo Keys…", "command-Delete Combo"]))

        try run(model, "Edit Combo Keys…")
        #expect(model.combos.draft?.combo == id && model.boardPick != nil)
        #expect(!model.canStartNewCombo && model.comboForKeys == nil, "a board pick takes the board's clicks")
        model.cancelComboDraft()

        try run(model, "Delete Combo")
        #expect(session.layout.combos.isEmpty && model.comboForKeys == nil)
        try run(model, "New Combo")
        #expect(model.combos.draft?.combo == nil && model.boardPick != nil)
    }

    @Test func macroCommandsNeedTheirPageAndAMacro() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        #expect(!model.canAddMacro && model.pageMacro == nil, "the Keys page")
        #expect(commandIDs(model, "macro").isDisjoint(with: ["command-New Macro", "command-Delete Macro"]))

        model.destination = .macros
        #expect(model.canAddMacro && model.pageMacro == nil && model.macroToRecordInto == nil, "no macros yet")
        try run(model, "New Macro")
        let locator = try #require(session.selection.macro)
        #expect(session.layout.macros.count == 1 && model.pageMacro == locator && model.macroToRecordInto == locator)
        #expect(commandIDs(model, "steps").contains("command-Record Steps…"))

        try run(model, "Record Steps…")
        #expect(model.macros.stepRecorder?.macro == locator && model.macroToRecordInto == nil, "already recording")
        model.stopRecordingSteps()

        // A full macro takes no more steps, as the page's Record Steps button says.
        for _ in 0..<Macro.maxSteps { session.insertStep(MacroStep(code: "KC_A"), at: 0, in: locator) }
        #expect(model.macroToRecordInto == nil && model.pageMacro == locator)

        try run(model, "Assign to Key…")
        #expect(model.boardPick != nil && model.page == nil, "the board, to pick the key")
        #expect(model.pageMacro == nil, "off the page")
        model.boardPick?.onCancel()
        model.boardPick = nil
        #expect(model.page == .macros)

        try run(model, "Delete Macro")
        #expect(session.layout.macros.isEmpty && model.pageMacro == nil)
    }
}
