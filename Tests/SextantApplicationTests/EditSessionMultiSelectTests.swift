import Foundation
import SextantApplication
import SextantDomain
import Testing

/// Multi-selection, copy and paste of keys, and Copy Layer To (spec §5.4, §5.5, §6.1; ADR 0047). The user's layout:
/// Main, Sym+Num and Brd+Sys; Main's 13 to 15 are A S D, 19 is Z with a held Option.
@MainActor
struct EditSessionMultiSelectTests {
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

    func step(_ undo: UndoManager, _ body: () -> Void) {
        undo.beginUndoGrouping()
        body()
        undo.endUndoGrouping()
    }

    @Test func togglingAndSelectingKeepAnAnchor() async throws {
        let (session, _) = try await open()
        session.select(keys: [19, 3, 7, 99])
        #expect(session.selection.keyIndex == 19 && session.selection.keyIndices == [3, 7, 19], "off-board keys are left out")
        session.toggle(key: 7)
        #expect(session.selection.keyIndices == [3, 19])
        session.toggle(key: 19)
        #expect(session.selection.keyIndex == 3 && session.selection.keyIndices == [3], "the anchor passes on")
        session.toggle(key: 12)
        #expect(session.selection.keyIndex == 3 && session.selection.keyIndices == [3, 12])
        session.select(key: 3, slot: .hold)
        #expect(session.selection.keyIndices == [3, 12] && session.selection.slot == .hold, "a slot change keeps the keys")
        session.select(key: 20)
        #expect(session.selection.keyIndices == [20], "another key collapses it")
        session.toggle(key: 20)
        #expect(session.selection.keyIndex == nil && session.selection.keyIndices.isEmpty)
        session.toggle(key: 5)
        #expect(session.selection.keyIndex == 5)

        session.select(keys: [13, 14, 15], anchor: 14)
        session.moveSelection(.right)
        #expect(session.selection.keyIndices.count == 1, "arrows collapse it")
        session.select(keys: [0, 6])
        session.moveSelection(.left)
        #expect(session.selection.keyIndices == [0], "even at the board's edge")
    }

    @Test func eachEditActsOnEverySelectedKeyAsOneUndoStep() async throws {
        let (session, undo) = try await open()
        let original = session.layout
        session.select(keys: [13, 14, 15])
        step(undo) { session.makeTransparent() }
        #expect(undo.undoActionName == "Make 3 Keys Transparent")
        #expect([13, 14, 15].allSatisfy { session.layout.key(layer: 0, index: $0) == .transparent })
        session.select(key: 40)
        undo.undo()
        #expect(session.layout == original)
        #expect(session.selection.keyIndices == [13, 14, 15], "undo brings the selection back")

        let names: [(String, () -> Void)] = [
            ("Disable 3 Keys", { session.disable() }),
            ("Set Tap on 3 Keys", { session.setCode("KC_Q") }),
            ("Set Hold on 3 Keys", { session.setHoldLayer(1) }),
            ("Clear Hold on 3 Keys", { session.setAction(nil, slot: .hold) }),
            ("Change Modifiers on 3 Keys", { session.setModifiers([.leftShift]) }),
            ("Set Color on 3 Keys", { session.setColor(HexColor(hex: "#FF0000")) }),
            ("Set Label on 3 Keys", { session.setLabel("Hi") }),
            ("Clear Label on 3 Keys", { session.setLabel(nil) }),
        ]
        for (name, edit) in names {
            step(undo, edit)
            #expect(undo.undoActionName == name)
        }
        #expect([13, 14, 15].allSatisfy { session.layout.key(layer: 0, index: $0)?.tap == .code("KC_Q", modifiers: [.leftShift]) })
        #expect(session.layout.key(layer: 0, index: 16) == original.key(layer: 0, index: 16))

        step(undo) { session.setLabel("One", index: 20) }
        #expect(undo.undoActionName == "Set Label", "a given key is that key alone")
        #expect(
            session.layout.key(layer: 0, index: 13)?.customLabel == nil && session.layout.key(layer: 0, index: 20)?.customLabel == "One")
    }

    @Test func setCodeKeepsEachKeysOwnChord() async throws {
        let (session, undo) = try await open()
        step(undo) { session.setCode("KC_A", modifiers: [.leftCommand], index: 13) }
        session.select(keys: [13, 14])
        step(undo) { session.setCode("KC_B") }
        #expect(session.layout.key(layer: 0, index: 13)?.tap == .code("KC_B", modifiers: [.leftCommand]))
        #expect(session.layout.key(layer: 0, index: 14)?.tap == .code("KC_B"))
        step(undo) { session.setAction { _ in .code("KC_C") } }
        #expect(undo.undoActionName == "Set Tap on 2 Keys")
        #expect(session.layout.key(layer: 0, index: 14)?.tap == .code("KC_C"))
    }

    @Test func overrideTakesTheInheritedKeysOfTheSelection() async throws {
        let (session, undo) = try await open()
        session.select(layer: 1)
        let inherited = (0..<52).filter { session.layout.resolvedKey(layer: 1, index: $0).isInherited }.prefix(2)
        let own = try #require((0..<52).first { !session.layout.resolvedKey(layer: 1, index: $0).own.isTransparent })
        session.select(keys: Array(inherited) + [own])
        step(undo) { session.overrideInherited() }
        #expect(undo.undoActionName == "Override 2 Keys")
        for i in inherited { #expect(session.layout.key(layer: 1, index: i) == session.layout.key(layer: 0, index: i)) }
    }

    @Test func copyToLayerPutsKeysInTheirPlaces() async throws {
        let (session, undo) = try await open()
        session.select(keys: [13, 19])
        step(undo) { session.copyKeys(toLayer: 2) }
        #expect(undo.undoActionName == "Copy 2 Keys to Brd+Sys")
        #expect(session.layout.key(layer: 2, index: 13) == session.layout.key(layer: 0, index: 13))
        #expect(session.layout.key(layer: 2, index: 19) == session.layout.key(layer: 0, index: 19))
        #expect(session.selection.layer == 0, "the shown layer stays, to copy again")
        let before = session.layout
        session.copyKeys(toLayer: 0)
        #expect(session.layout == before, "not onto its own layer")
    }

    @Test func cutCopyAndPaste() async throws {
        let (session, undo) = try await open()
        let main = session.layout.layers[0].keys
        session.select(keys: [13, 19])
        let copied = try #require(session.copiedKeys)
        #expect(copied.entries.map(\.index) == [13, 19] && copied.entries.map(\.key) == [main[13], main[19]])

        // Several keys go back to their own places on the shown layer, and are selected.
        session.select(layer: 2)
        session.select(key: 0)
        step(undo) { #expect(session.pasteKeys(copied)) }
        #expect(undo.undoActionName == "Paste 2 Keys")
        #expect(session.layout.key(layer: 2, index: 13) == main[13] && session.layout.key(layer: 2, index: 19) == main[19])
        #expect(session.selection.keyIndices == [13, 19])
        undo.undo()
        #expect(session.selection.keyIndices == [0], "undo selects what was selected before")
        undo.redo()
        #expect(session.selection.keyIndices == [13, 19], "redo selects where the paste went")

        // One key goes onto every selected key.
        let one = try #require(CopiedKeys(layout: session.layout, layer: 0, indices: [24]))
        session.select(keys: [1, 2, 3])
        step(undo) { session.pasteKeys(one) }
        #expect(undo.undoActionName == "Paste onto 3 Keys")
        #expect([1, 2, 3].allSatisfy { session.layout.key(layer: 2, index: $0) == main[24] })
        session.select(key: 4)
        step(undo) { session.pasteKeys(one) }
        #expect(undo.undoActionName == "Paste Key")

        // Several keys from another board have no places here.
        let other = CopiedKeys(board: "moonlander", keyCount: 72, entries: copied.entries)
        #expect(!session.pasteKeys(other))

        session.select(layer: 0)
        session.select(keys: [13, 19])
        var cut: CopiedKeys?
        step(undo) { cut = session.cutKeys() }
        #expect(undo.undoActionName == "Cut 2 Keys" && cut == copied)
        #expect(session.layout.key(layer: 0, index: 13) == .transparent)
        undo.undo()
        #expect(session.layout.layers[0].keys == main)
    }

    @Test func pasteNeedsASelectedKeyAndShowsWhereSeveralKeysWent() async throws {
        let (session, undo) = try await open()
        session.select(keys: [13, 14, 15])
        let copied = try #require(session.copiedKeys)
        // Back on the layer they came from they change nothing, but the keys they went to are still selected.
        session.select(key: 40)
        let before = session.layout
        #expect(session.pasteKeys(copied))
        #expect(session.layout == before && session.selection.keyIndices == [13, 14, 15])
        #expect(undo.canUndo == false, "no undo step for a paste that changes nothing")

        // With no key selected there is nowhere to paste.
        session.select(key: nil)
        session.select(layer: 2)
        let layer2 = session.layout
        #expect(!session.pasteKeys(copied))
        #expect(!session.pasteKeys(try #require(CopiedKeys(layout: before, layer: 0, indices: [13]))))
        #expect(session.layout == layer2)
    }

    /// Where the window shows one key (another lens, a pick), a multi-selection that undo or a paste brings back acts as
    /// its anchor: edits, copy and the count never reach keys without a ring.
    @Test func aWindowShowingOneKeyLimitsEveryEditToTheAnchor() async throws {
        let (session, undo) = try await open()
        let main = session.layout.layers[0].keys
        session.select(keys: [13, 14, 15], anchor: 13)
        step(undo) { session.setLabel("X") }
        let window = ShownKeys()
        session.showsSeveralKeys = { window.several }
        #expect(session.selectedKeys == [13])
        undo.undo()
        #expect(session.selection.keyIndices == [13, 14, 15] && session.selectedKeys == [13])
        step(undo) { session.makeTransparent() }
        #expect(undo.undoActionName == "Make Transparent")
        #expect(session.layout.key(layer: 0, index: 13) == .transparent)
        #expect(session.layout.key(layer: 0, index: 14) == main[14] && session.layout.key(layer: 0, index: 15) == main[15])
        #expect(session.copiedKeys?.entries.map(\.index) == [13])
        window.several = true
        #expect(session.selectedKeys == [13, 14, 15], "the others come back where several keys show")
    }

    /// What the window says about showing several keys.
    @MainActor final class ShownKeys {
        var several = false
    }

    @Test func goingToAKeySelectsItAlone() async throws {
        let (session, _) = try await open()
        session.select(keys: [13, 14, 15], anchor: 13)
        session.select(layer: 1)
        session.select(keys: [13], slot: .hold)
        #expect(session.selection.keyIndices == [13] && session.selection.slot == .hold)
        session.select(keys: [13, 14, 15], anchor: 13)
        session.selectRange(to: 15)
        #expect(session.selection.keyIndices == [13, 14, 15] && session.selection.keyIndex == 13)
        session.select(key: nil)
        session.selectRange(to: 15)
        #expect(session.selection.keyIndices == [15], "no anchor: that key alone")
    }

    @Test func pastedLayerKeysForLayersThisLayoutLacksDoNothing() async throws {
        let (session, undo) = try await open()
        let copied = CopiedKeys(
            board: "voyager", keyCount: 52, entries: [.init(index: 5, key: Key(tap: .code("KC_A"), hold: .momentary(7)))])
        session.select(key: 5)
        step(undo) { session.pasteKeys(copied) }
        #expect(session.layout.key(layer: 0, index: 5) == Key(tap: .code("KC_A"), hold: KeyAction.none))
    }

    @Test func copyLayerToKeepsTheTargetsNameAndColor() async throws {
        let (session, undo) = try await open()
        let target = session.layout.layers[2]
        step(undo) { session.copyLayer(1, to: 2) }
        #expect(undo.undoActionName == "Copy Layer to Brd+Sys")
        let copied = session.layout.layers[2]
        #expect(copied.keys == session.layout.layers[1].keys)
        #expect(copied.id == target.id && copied.title == target.title && copied.color == target.color)
        #expect(session.selection.layer == 2, "it shows the layer copied to")
        undo.undo()
        #expect(session.layout.layers[2] == target && session.selection.layer == 0)

        let before = session.layout
        session.copyLayer(1, to: 1)
        #expect(session.layout == before, "not onto itself")

        step(undo) { #expect(session.appendLayer(copying: 1) == 3) }
        #expect(undo.undoActionName == "Copy Layer to New Layer")
        let added = session.layout.layers[3]
        #expect(added.title == "Sym+Num Copy" && added.keys == session.layout.layers[1].keys && added.id != session.layout.layers[1].id)
        #expect(session.selection.layer == 3)
    }

    @Test func aMacroGoesOntoEverySelectedKey() async throws {
        let (session, undo) = try await open()
        step(undo) { session.newMacro() }
        let draft = try #require(session.selection.macro)
        step(undo) { session.insertStep(MacroStep(code: "KC_K"), at: 0, in: draft) }
        session.select(keys: [13, 14, 15], anchor: 14)
        step(undo) { session.assignMacroToSelectedKeys(draft) }
        #expect(undo.undoActionName == "Assign Macro to 3 Keys")
        #expect(session.layout.macroDrafts.isEmpty, "the draft moves")
        for i in [13, 14, 15] { #expect(session.layout.key(layer: 0, index: i)?.tap?.macro?.steps == [MacroStep(code: "KC_K")]) }
        #expect(session.selection.macro == .key(KeyRef(layer: 0, index: 14, slot: .tap)), "selected on the anchor")
        undo.undo()
        #expect(session.layout.macroDrafts.count == 1)
    }

    /// Oryx has no drafts: re-importing keeps the macros on no key yet.
    @Test func importingFromOryxKeepsTheDrafts() async throws {
        let (session, undo) = try await open()
        step(undo) { session.newMacro() }
        let drafts = session.layout.macroDrafts
        var imported = try KeyboardLayout(oryxJSON: Fixtures.userLayoutData)
        imported.layers[0].keys[13] = Key("KC_Q")
        undo.beginUndoGrouping()
        try await session.applyImport(imported)
        undo.endUndoGrouping()
        #expect(session.layout.macroDrafts == drafts && drafts.count == 1)
        #expect(session.layout.key(layer: 0, index: 13) == Key("KC_Q"))
        #expect(!session.isEditedSinceRevision)
    }
}
