import Foundation
import SextantApplication
import SextantDomain
import Testing

@testable import SextantUI

/// The Combos page's window-model side (spec §6.4, ADR 0046): making a combo through the board pick and the picker, the
/// Esc ladder, the caps' rings and numbers, ⌘K's Documents rows, and where the output pills go.
@MainActor
struct CombosLensTests {
    /// Main's J, K and L.
    let j = 39, k = 40, l = 41

    @Test func newComboPicksKeysThenItsOutput() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        let undo = UndoManager()
        session.undoManager = undo
        session.select(key: 19)
        model.startNewCombo()
        #expect(model.page == .combos && model.boardPick?.prompt == "Click 2–6 keys, then Choose Output · esc cancels")
        model.click(key: j)
        #expect(!model.canFinishDraft, "one key isn't a combo")
        model.chooseNewComboOutput()
        #expect(model.palette == nil)
        model.click(key: k)
        model.click(key: l)
        model.click(key: l)
        #expect(model.combos.draft?.keys == [j, k] && model.boardPick != nil, "a second click takes a key out; the pick goes on")
        #expect(session.selection.keyIndex == 19, "a pick never selects")

        model.chooseNewComboOutput()
        #expect(model.isPicking && model.pickerTarget == "Combo 1 › Output" && model.pickerCurrent == "Now empty")
        model.palette?.query = "esc"
        model.runHighlighted(advance: true)
        let combo = try #require(session.layout.combos.first)
        #expect(combo.keyIndices == [j, k] && combo.output == .code("KC_ESCAPE") && combo.layer == 0)
        #expect(session.selection.combo == combo.id && model.boardPick == nil && model.combos.draft == nil && model.palette == nil)
        #expect(undo.undoActionName == "New Combo")
        #expect(session.selection.keyIndex == 19, "the selected key never changes")
    }

    @Test func aPickerClosedWithoutAChoiceKeepsTheKeys() async throws {
        let model = try await openUserLayout()
        model.startNewCombo()
        model.click(key: j)
        model.click(key: k)
        model.chooseNewComboOutput()
        model.closePalette()
        #expect(model.combos.draft?.keys == [j, k] && model.boardPick != nil && model.session?.layout.combos.isEmpty == true)
    }

    /// Spec §9.3: esc cancels the gesture (step 4), then deselects the key (step 5).
    @Test func escCancelsTheComboThenDeselects() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        session.select(key: 3)
        model.startNewCombo()
        model.click(key: j)
        model.escapeBoard()
        #expect(model.boardPick == nil && model.combos.draft == nil && session.layout.combos.isEmpty && model.page == .combos)
        #expect(session.selection.keyIndex == 3)
        model.escapeBoard()
        #expect(session.selection.keyIndex == nil)
    }

    @Test func aComboTakesAtMostSixKeys() async throws {
        let model = try await openUserLayout()
        model.startNewCombo()
        for key in 1...7 { model.click(key: key) }
        #expect(model.combos.draft?.keys == Array(1...6))
    }

    @Test func editKeysChangesThemOnDone() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        let id = session.newCombo(keys: [j, k], layer: 1, output: .code("KC_TAB"))
        model.destination = .combos
        model.editComboKeys(id)
        #expect(session.selection.layer == 1, "the board shows the layer the combo reads")
        model.click(key: l)
        model.click(key: j)
        #expect(session.layout.combo(id: id)?.keyIndices == [j, k], "nothing changes before Done")
        model.finishComboKeys()
        #expect(session.layout.combo(id: id)?.keyIndices == [k, l] && model.boardPick == nil)

        model.editComboKeys(id)
        model.click(key: l)
        #expect(!model.canFinishDraft)
        model.finishComboKeys()
        #expect(model.boardPick != nil && session.layout.combo(id: id)?.keyIndices == [k, l], "Done needs 2 keys")
    }

    @Test func membersAreRingedAndNumberedAndTheRestDimmed() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        model.destination = .combos
        #expect(model.capDecoration(layer: 0, index: 0) == CapDecoration(), "with no combo, no key is dimmed")
        let first = session.newCombo(keys: [j, k], layer: 0, output: .code("KC_ESCAPE"))
        let second = session.newCombo(keys: [k, l], layer: 0, output: .code("KC_ENTER"))
        session.selectCombo(nil)
        let jDecoration = model.capDecoration(layer: 0, index: j), kDecoration = model.capDecoration(layer: 0, index: k)
        #expect(jDecoration.ring == Tokens.combo(0) && jDecoration.number?.symbol == "1.circle.fill" && jDecoration.opacity == 1)
        #expect(kDecoration.number?.symbol == "1.circle.fill", "a key in two combos takes the lower number")
        #expect(kDecoration.number?.accessibilityText == "in combo 1: J + K → Escape; in combo 2: K + L → Return")
        #expect(model.capDecoration(layer: 0, index: l).ring == Tokens.combo(1))
        #expect(model.capDecoration(layer: 0, index: 0).opacity == 0.45)

        // A selected combo is drawn alone.
        session.selectCombo(second)
        #expect(model.capDecoration(layer: 0, index: j).opacity == 0.45 && model.capDecoration(layer: 0, index: k).ring == Tokens.combo(1))
        // The filter: only combos reading the shown layer.
        session.selectCombo(nil)
        model.combos.showsAllLayers = false
        session.select(layer: 1)
        #expect(model.shownCombos.isEmpty && model.capDecoration(layer: 1, index: j) == CapDecoration())
        session.setComboLayer(1, in: first)
        #expect(model.shownCombos.map(\.number) == [1])

        // Other pages draw plain caps.
        model.destination = .layer(0)
        #expect(model.capDecoration(layer: 0, index: j) == CapDecoration())
    }

    /// SF Symbols squeezes two digits past reading on a cap, and circles numbers only up to 50: from 10 the number is text.
    @Test func twoDigitNumbersAreText() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        model.destination = .combos
        for _ in 0..<50 { session.newCombo(keys: [1, 2], layer: 0, output: .code("KC_A")) }
        let last = session.newCombo(keys: [j, k], layer: 0, output: .code("KC_B"))
        session.selectCombo(last)
        #expect(model.capDecoration(layer: 0, index: j).number?.text == "51")
        session.selectCombo(session.layout.combos[9].id)
        #expect(model.capDecoration(layer: 0, index: 1).number?.text == "10")
        session.selectCombo(session.layout.combos[8].id)
        let nine = try #require(model.capDecoration(layer: 0, index: 1).number)
        #expect(nine.text == nil && nine.symbol == "9.circle.fill")
    }

    /// A click selects a combo through click(key:), so a key already selected still selects its combo (spec §6.4).
    @Test func clickingAMemberSelectsItsCombo() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        session.select(key: j)
        model.destination = .combos
        let first = session.newCombo(keys: [j, k], layer: 0, output: .code("KC_ESCAPE"))
        let second = session.newCombo(keys: [k, l], layer: 0, output: .code("KC_ENTER"))
        session.selectCombo(nil)
        model.click(key: j)
        #expect(session.selection.combo == first, "the key carried over from the layer is already selected")
        model.click(key: l)
        #expect(session.selection.combo == second)
        model.click(key: k)
        #expect(session.selection.combo == second, "the selected combo keeps a key they share")
        model.selectCombo(first)
        model.selectCombo(second)
        model.click(key: k)
        model.click(key: j)
        #expect(session.selection.combo == first)
        model.click(key: 0)
        model.click(key: 0)
        #expect(session.selection.combo == nil)
    }

    /// The board shows a selected combo's layer, however it was selected, and a combo whose layer isn't shown isn't
    /// selected on the page (spec §6.4).
    @Test func theBoardShowsTheSelectedCombosLayer() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        model.destination = .combos
        let main = session.newCombo(keys: [j, k], layer: 0, output: .code("KC_ESCAPE"))
        let symNum = session.newCombo(keys: [l, 42], layer: 1, output: .code("KC_TAB"))
        session.selectCombo(nil)
        session.select(layer: 0)
        model.click(key: l)
        #expect(session.selection.combo == symNum && session.selection.layer == 1, "a click shows the layer its combo reads")
        model.setComboLayer(2, of: symNum)
        #expect(session.layout.combo(id: symNum)?.layer == 2 && session.selection.layer == 2, "Keys from shows its layer")
        #expect(model.selectedPageCombo?.id == symNum && model.focusedCombos.map(\.id) == [symNum])

        model.showCombos(fromLayer: 0)
        #expect(model.selectedPageCombo == nil, "a combo on a layer the board doesn't show isn't on the page")
        #expect(model.focusedCombos.map(\.id) == [main], "the board draws what the filter shows")
        model.showCombos(fromLayer: 2)
        #expect(model.selectedPageCombo?.id == symNum, "its layer brings it back")

        // A click prefers a combo reading the shown layer.
        model.showCombos(fromLayer: nil)
        session.setComboLayer(0, in: symNum)
        let other = session.newCombo(keys: [j, 43], layer: 1, output: .code("KC_A"))
        session.selectCombo(nil)
        session.select(layer: 1)
        model.click(key: j)
        #expect(session.selection.combo == other && session.selection.layer == 1)
    }

    /// Esc goes back to every combo before it deselects the key (spec §9.3).
    @Test func escShowsEveryComboAgainThenDeselects() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        model.destination = .combos
        let id = session.newCombo(keys: [j, k], layer: 0, output: .code("KC_ESCAPE"))
        session.selectCombo(nil)
        model.click(key: j)
        #expect(session.selection.combo == id)
        model.escapeBoard()
        #expect(session.selection.combo == nil && session.selection.keyIndex == j)
        model.escapeBoard()
        #expect(session.selection.keyIndex == nil)
    }

    /// Undo that takes the combo whose keys are changing ends Edit Keys: Done would change nothing.
    @Test func undoTakingTheCombosEndsEditKeys() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        let undo = UndoManager()
        undo.groupsByEvent = false
        session.undoManager = undo
        model.destination = .combos
        undo.beginUndoGrouping()
        let id = session.newCombo(keys: [j, k], layer: 0, output: .code("KC_ESCAPE"))
        undo.endUndoGrouping()
        model.editComboKeys(id)
        model.click(key: l)
        undo.undo()
        #expect(model.draftCombo == nil && !model.canFinishDraft)
        model.endDraftOfRemovedCombo()
        #expect(model.combos.draft == nil && model.boardPick == nil)
    }

    /// Among several combos, a line passing under another cap is left out; drawn alone, a combo keeps it.
    @Test func overviewTracesNeverRunUnderOtherCaps() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        let board = session.geometry.layout(keySize: 50, spacing: 5.5)
        let f = 16
        let apart = NumberedCombo(number: 1, combo: Combo(keyIndices: [f, j], output: .code("KC_A")))
        let beside = NumberedCombo(number: 2, combo: Combo(keyIndices: [j, k, l], output: .code("KC_B")))
        #expect(ComboPills.trace(apart, board: board, alone: false).isEmpty, "F to J passes under G and H")
        #expect(ComboPills.trace(apart, board: board, alone: true).count == 1)
        #expect(ComboPills.trace(beside, board: board, alone: false).count == 2)
    }

    /// A combo whose keys show other combos' numbers and that no line joins to its own number gets its number beside
    /// theirs on each such key; a key showing its number anchors the keys a line joins to it.
    @Test func numbersNoCapOrTraceShowsGoBesideTheCapsOwn() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        let board = session.geometry.layout(keySize: 50, spacing: 5.5)
        let f = 16, d = 15, g = 17
        let jk = NumberedCombo(number: 1, combo: Combo(keyIndices: [j, k], output: .code("KC_A")))
        let df = NumberedCombo(number: 2, combo: Combo(keyIndices: [d, f], output: .code("KC_B")))
        let fj = NumberedCombo(number: 3, combo: Combo(keyIndices: [f, j], output: .code("KC_C")))
        let fg = NumberedCombo(number: 4, combo: Combo(keyIndices: [f, g], output: .code("KC_D")))
        let strays = ComboPills.strayNumbers([jk, df, fj, fg], board: board)
        #expect(strays.map(\.id).sorted() == ["\(fj.id)-\(f)", "\(fj.id)-\(j)"], "G shows 4 and a line joins it to F")
        let besideF = try #require(strays.first { $0.key == f }?.center)
        let fFrame = board.frames[f]
        #expect(abs(besideF.x - (fFrame.center.x - 25 + 18)) < 0.5 && abs(besideF.y - (fFrame.center.y - 25 + 3)) < 0.5)
        #expect(ComboPills.strayNumbers([fj], board: board).isEmpty, "a combo drawn alone shows its number on every key")
    }

    @Test func paletteFindsCombos() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        let id = session.newCombo(keys: [j, k], layer: 0, output: .code("KC_ESCAPE"))
        session.renameCombo(id, to: "Escape")
        session.selectCombo(nil)
        model.openPalette(query: "escape")
        let row = try #require(model.paletteItems.first { $0.id == "document-combo-\(id)" })
        #expect(row.title == "Escape" && row.detail == "J + K → Esc" && row.note == "Keys from Main")
        row.perform()
        #expect(model.page == .combos && session.selection.combo == id && model.palette == nil)
    }

    // MARK: Pills

    /// The board area of a window, as BoardView lays the board out in it, in board points.
    func board(_ session: EditSession, area size: CGSize) -> (BoardLayout, CGRect) {
        let cap = BoardView.capSize(for: size, boardUnits: session.geometry.bounds.size, range: 36...76)
        let board = session.geometry.layout(keySize: cap, spacing: cap * 0.11)
        let origin = CGPoint(x: size.width / 2 - board.size.width / 2, y: size.height * 0.46 - board.size.height / 2)
        return (board, CGRect(origin: CGPoint(x: -origin.x, y: -origin.y), size: size).insetBy(dx: 4, dy: 4))
    }

    /// No pill covers a legend, a number or another pill, and each stays in the board area.
    func expectClear(_ layout: KeyboardLayout, session: EditSession, size: CGSize, placesAll: Bool, _ label: String) {
        let (board, area) = board(session, area: size)
        let combos = layout.combos.enumerated().map { NumberedCombo(number: $0.offset + 1, combo: $0.element) }
        for layer in Set(layout.combos.map(\.keysLayer)) {
            let legends = ComboPills.legendRects(layout: layout, layer: layer, mode: .symbols, board: board)
            let pills = ComboPills.place(combos, layout: layout, legends: legends, board: board, area: area)
            let strays = ComboPills.strayNumbers(combos, board: board).map {
                CGRect(x: $0.center.x - 7, y: $0.center.y - 7, width: 14, height: 14)
            }
            let numbers =
                board.frames.filter { f in layout.combos.contains { $0.keyIndices.contains(f.index) } }.map(ComboPills.numberRect) + strays
            for pill in pills {
                #expect(!legends.contains { $0.intersects(pill.rect) }, "\(label): pill \(pill.item.number) covers a legend")
                #expect(!numbers.contains { $0.intersects(pill.rect) }, "\(label): pill \(pill.item.number) covers a number")
                #expect(area.contains(pill.rect), "\(label): pill \(pill.item.number) leaves the board area")
                #expect(!pills.contains { $0.item.id != pill.item.id && $0.rect.intersects(pill.rect) }, "\(label): pills overlap")
            }
            if placesAll { #expect(pills.count == combos.count, "\(label): \(pills.count) of \(combos.count) pills placed") }
        }
    }

    /// A dense set on the user's layout: every pair of neighbours on the letter rows of both halves, and two across.
    static func denseCombos(_ layout: KeyboardLayout) -> KeyboardLayout {
        var layout = layout
        let outputs = ["KC_ESCAPE", "KC_ENTER", "KC_TAB", "KC_BSPC", "KC_DELETE", "KC_LBRC", "KC_RBRC", "KC_MINUS"]
        for half in [0, 26] {
            for row in 1...3 {
                for column in 0..<5 {
                    let first = half + row * 6 + column
                    layout.addCombo(Combo(keyIndices: [first, first + 1], output: .code(outputs[layout.combos.count % outputs.count])))
                }
            }
        }
        layout.addCombo(Combo(keyIndices: [16, 39], output: KeyAction(code: "KC_C", modifiers: [.leftCommand])))
        layout.addCombo(Combo(keyIndices: [14, 15, 16, 39, 40, 41], output: .momentary(2)))
        return layout
    }

    @Test func pillsNeverCoverALegendOnADenseBoard() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        let layout = Self.denseCombos(session.layout)
        #expect(layout.combos.count == 32)
        expectClear(layout, session: session, size: CGSize(width: 900, height: 660), placesAll: true, "full window")
        expectClear(layout, session: session, size: CGSize(width: 640, height: 400), placesAll: false, "minimum window")
    }

    @Test(.enabled(if: referenceExamples != nil, "needs SEXTANT_REFERENCE"))
    func pillsNeverCoverALegendOnJRGQm() async throws {
        let library = Library(store: MemoryLibrary())
        _ = try await library.importOryxJSON(Data(contentsOf: exampleURL("voyager-JRGQm.json")))
        let model = LayoutWindowModel(library: library)
        await model.open(nil)
        let session = try #require(model.session)
        #expect(session.layout.combos.count == 32)
        expectClear(session.layout, session: session, size: CGSize(width: 900, height: 660), placesAll: true, "full window")
        expectClear(session.layout, session: session, size: CGSize(width: 640, height: 400), placesAll: false, "minimum window")
    }

    @Test func treesJoinEveryKey() {
        let points = [CGPoint.zero, CGPoint(x: 10, y: 0), CGPoint(x: 0, y: 10), CGPoint(x: 30, y: 0)]
        let edges = ComboPills.tree(points)
        #expect(edges.count == 3)
        #expect(edges.contains { $0 == (1, 3) }, "the far key joins its nearest")
        #expect(ComboPills.tree([]).isEmpty && ComboPills.tree([.zero]).isEmpty)
    }
}
