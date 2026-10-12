import Foundation
import SextantApplication
import SextantDomain
import Testing

@testable import SextantUI

/// The Macros page's window-model side (spec §6.3, ADR 0042): the step picker, Assign to Key's board pick, the picker's
/// Macros category and ⌘K's Documents group.
@MainActor
struct MacrosPageTests {
    /// "Teams Cam", JRGQm's AppMedia key 32.
    let teamsCam = MacroLocator.key(KeyRef(layer: 2, index: 32, slot: .tap))

    func open(_ files: String...) async throws -> LayoutWindowModel {
        let library = Library(store: MemoryLibrary())
        let examples = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "docs/research/oryx-examples")
        for file in files { _ = try await library.importOryxJSON(Data(contentsOf: examples.appending(path: file))) }
        let model = LayoutWindowModel(library: library)
        await model.open(library.entries.first { $0.title == "Analyst Developer" }?.id)
        return model
    }

    @Test func theStepPickerOffersOnlyKeysAStepCanType() async throws {
        let model = try await open("voyager-JRGQm.json")
        let session = try #require(model.session)
        model.destination = .macros
        session.select(key: 7)
        model.openStepPicker(step: 1, in: teamsCam)
        #expect(model.isPicking && model.pickerTarget == "Teams Cam › Step 2" && model.pickerCurrent == "Now LCTL(LGUI(KC_2))")
        let suggested = model.paletteItems.compactMap(\.keycode?.code)
        #expect(!suggested.isEmpty && suggested.allSatisfy(MacroStep.canType), "\(suggested)")
        #expect(model.pickerCount(.layers) == 0 && model.pickerCount(.macros) == 0 && model.pickerCount(.letters) == 26)
        model.palette?.query = "reset"
        let found = model.paletteItems.compactMap(\.keycode?.code)
        #expect(!found.contains("QK_BOOT") && found.allSatisfy(MacroStep.canType), "QK_BOOT has no X_ name")
        model.palette?.query = "q"
        model.runHighlighted(advance: true)
        #expect(model.palette == nil, "⌘⏎ assigns and closes: a step has no next key")
        #expect(
            session.layout.macro(at: teamsCam)?.steps[1] == MacroStep(code: "KC_Q", modifiers: [.leftControl, .leftCommand], delay: 100))
        #expect(session.selection.keyIndex == 7, "the selected key never changes")

        // Add Step goes after the selected step.
        session.selectMacro(teamsCam, step: 0)
        model.openStepPicker(step: nil, in: teamsCam)
        model.palette?.query = "z"
        model.runHighlighted()
        #expect(session.layout.macro(at: teamsCam)?.steps.map(\.code) == ["KC_1", "KC_Z", "KC_Q", "KC_O"])
        #expect(session.selection.step == 1)
    }

    @Test func assignToKeyPicksOnTheBoardAndComesBack() async throws {
        let model = try await open("voyager-JRGQm.json")
        let session = try #require(model.session)
        session.select(layer: 1)
        model.destination = .macros
        session.newMacro()
        let draft = try #require(session.selection.macro)
        model.assignMacroToKey(draft)
        #expect(model.page == nil && model.boardPick?.prompt == "Click a key to play ‘Empty Macro’ on tap · esc cancels")
        model.escapeBoard()
        #expect(model.boardPick == nil && model.page == .macros && session.selection.macro == draft, "esc cancels and comes back")

        model.assignMacroToKey(draft)
        model.click(key: 20)
        let placed = MacroLocator.key(KeyRef(layer: 1, index: 20, slot: .tap))
        #expect(model.boardPick == nil && model.page == .macros)
        #expect(session.selection.macro == placed && session.layout.macroDrafts.isEmpty)
        #expect(session.layout.key(layer: 1, index: 20)?.kind == .macro)
    }

    /// Opening another layout cancels the pick; the page it started on belongs to the old layout.
    @Test func anotherLayoutEndsThePickOnItsBoard() async throws {
        let model = try await open("voyager-JRGQm.json", "voyager-XlrR4.json")
        model.destination = .macros
        model.assignMacroToKey(teamsCam)
        let other = try #require(model.library.entries.first { $0.title != "Analyst Developer" })
        await model.open(other.id)
        #expect(model.boardPick == nil && model.page == nil)
    }

    @Test func theMacrosCategoryPutsAMacroOnTheSelectedKeysTap() async throws {
        let model = try await open("voyager-JRGQm.json")
        let session = try #require(model.session)
        session.select(layer: 0)
        session.select(key: 19, slot: .hold)
        model.openKeycodePicker()
        model.palette?.category = .macros
        #expect(model.pickerCount(.macros) == 67 && model.paletteItems.count == 67)
        let item = try #require(model.paletteItems.first { $0.title == "Teams Cam" })
        #expect(item.keycode == nil && item.note == "AppMedia · key 32")
        model.run(item)
        let key = try #require(session.layout.key(layer: 0, index: 19))
        #expect(model.palette == nil && key.tap?.macro?.steps == session.layout.macro(at: teamsCam)?.steps && key.hold == nil)
        #expect(key.tap?.macro?.name == "Teams Cam", "the copy takes its key's label as its name")
        model.openKeycodePicker()
        model.palette?.category = .macros
        model.palette?.query = "teams"
        #expect(model.paletteItems.map(\.note) == ["QWERTY · key 19", "AppMedia · key 32", "AppMedia · key 44"])
    }

    @Test func documentsFindMacrosAndOpenThem() async throws {
        let model = try await open("voyager-JRGQm.json")
        model.openPalette(query: "teams cam")
        let row = try #require(model.paletteItems.first { $0.group == .documents })
        #expect(row.title == "Teams Cam" && row.detail == "3 steps · 300 ms")
        model.run(row)
        #expect(model.palette == nil && model.destination == .macros && model.session?.selection.macro == teamsCam)
        model.openPalette(query: "macro")
        #expect(model.paletteItems.filter { $0.group == .documents }.count == 5)
    }

    @Test func macroTextReadsAsTheSpecShowsIt() throws {
        let macro = Macro(
            steps: [MacroStep(code: "KC_O", modifiers: [.leftShift, .leftCommand], delay: 150)]
                + "keymap".map { MacroStep(code: "KC_\($0.uppercased())") }
                + [MacroStep(code: "KC_SPACE", delay: 60)], endsWithEnter: true)
        #expect(MacroText.typed(macro) == "⇧⌘O ⧗150 k e y m a p ␣ ⧗60 ⏎")
        #expect(MacroText.title(macro) == "“⇧⌘Okeymap␣”")
        #expect(MacroText.stats(macro) == "8 steps · 210 ms")
        let layout = try KeyboardLayout(oryxJSON: #require(userLayoutData))
        let place = MacroLocator.key(KeyRef(layer: 2, index: 17, slot: .tap))
        #expect(MacroText.summary(macro, at: place, in: layout) == "8/24 steps · ≈0.29 s · plays on tap of Brd+Sys key 17")
        #expect(MacroText.place(.draft("x"), in: layout) == "not on a key yet")
    }
}
