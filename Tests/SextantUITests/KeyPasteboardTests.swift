import AppKit
import Foundation
import SextantApplication
import SextantDomain
import Testing

@testable import SextantUI

/// Multi-select on the board, and cut, copy and paste of keys (spec §5.4, §5.5; ADR 0047). Every pasteboard here is a
/// uniquely named one, never the general pasteboard.
@MainActor
struct KeyPasteboardTests {
    /// A private pasteboard, released when the test ends.
    final class Board {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.sextant.tests.\(UUID().uuidString)"))
        deinit { pasteboard.releaseGlobally() }
    }

    /// What SwiftUI's copy command does with the item providers: replaces the pasteboard's contents with each of their
    /// representations, under its type.
    func put(_ providers: [NSItemProvider], on pasteboard: NSPasteboard) async {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        for provider in providers {
            for type in provider.registeredTypeIdentifiers {
                let data = await withCheckedContinuation { done in
                    _ = provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in done.resume(returning: data) }
                }
                if let data { item.setData(data, forType: NSPasteboard.PasteboardType(type)) }
            }
        }
        pasteboard.writeObjects([item])
    }

    @Test func copyWritesBothFlavorsAndPasteReadsThemBack() async throws {
        let board = Board()
        let model = try await openUserLayout()
        let session = try #require(model.session)
        let main = session.layout.layers[0].keys
        session.select(keys: [13, 24])
        await put(model.copyKeys(), on: board.pasteboard)
        #expect(board.pasteboard.types?.contains(KeyPasteboard.type) == true)
        #expect(board.pasteboard.string(forType: .string) == "KC_A, LT(1, KC_ENTER)")
        #expect(try KeyPasteboard.read(from: board.pasteboard)?.entries.map(\.key) == [main[13], main[24]])

        session.select(layer: 2)
        session.select(key: 0)
        #expect(model.pasteKeys(from: board.pasteboard))
        #expect(session.layout.key(layer: 2, index: 13) == main[13] && session.layout.key(layer: 2, index: 24) == main[24])
        #expect(session.selection.keyIndices == [13, 24])
    }

    @Test func cutEmptiesTheKeys() async throws {
        let board = Board()
        let model = try await openUserLayout()
        let session = try #require(model.session)
        let z = session.layout.key(layer: 0, index: 19)
        session.select(key: 19)
        await put(model.cutKeys(), on: board.pasteboard)
        #expect(session.layout.key(layer: 0, index: 19) == .transparent)
        #expect(try KeyPasteboard.read(from: board.pasteboard)?.entries.first?.key == z)
    }

    @Test func pasteRefusesWhatIsntSafeAndIgnoresText() async throws {
        let board = Board()
        let model = try await openUserLayout()
        let session = try #require(model.session)
        session.select(key: 5)
        let before = session.layout
        board.pasteboard.clearContents()
        board.pasteboard.setString("KC_A", forType: .string)
        #expect(try KeyPasteboard.read(from: board.pasteboard) == nil)
        #expect(!model.pasteKeys(from: board.pasteboard), "plain text isn't keys")
        board.pasteboard.clearContents()
        let key = #"{"index":5,"key":{"tap":{"code":"KC_A); x();"}}}"#
        let hostile = #"{"format":"com.sextant.keys","version":1,"board":"voyager","keyCount":52,"keys":[\#(key)]}"#
        board.pasteboard.setData(Data(hostile.utf8), forType: KeyPasteboard.type)
        #expect(throws: CopiedKeysError.badAction(index: 5)) { try KeyPasteboard.read(from: board.pasteboard) }
        #expect(!model.pasteKeys(from: board.pasteboard))
        #expect(session.layout == before)

        // Nothing to copy without a key, or on a page.
        session.select(key: nil)
        #expect(model.copyKeys().isEmpty)
        session.select(key: 5)
        model.destination = .firmwareSettings
        #expect(model.copyKeys().isEmpty && model.cutKeys().isEmpty)
    }

    // MARK: Selecting on the board

    @Test func shiftClickSelectsInReadingOrderAndCommandClickToggles() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        let geometry = session.geometry
        let order = BoardView.readingOrder(geometry)
        let sorted = order.indices.sorted { order[$0] > order[$1] }
        model.click(key: sorted[3])
        model.click(key: sorted[9], .range)
        #expect(Set(session.selection.keyIndices) == Set(sorted[3...9]), "the run between them, as VoiceOver reads the board")
        #expect(session.selection.keyIndex == sorted[3], "the anchor stays")
        // Back past the anchor: the range turns around it.
        model.click(key: sorted[1], .range)
        #expect(Set(session.selection.keyIndices) == Set(sorted[1...3]))
        // Across halves: the left half's thumbs come before the right half.
        let lastLeft = try #require(sorted.lastIndex { geometry.key($0).hand == .left })
        model.click(key: sorted[lastLeft + 1], .range)
        #expect(session.selection.keyIndices.count == lastLeft + 1 - 3 + 1)

        model.click(key: 40, .toggle)
        #expect(session.selection.keyIndices.contains(40))
        model.click(key: 40, .toggle)
        #expect(!session.selection.keyIndices.contains(40))
        model.click(key: 40)
        #expect(session.selection.keyIndices == [40], "a plain click selects one key")
        #expect(model.selectedKeyCount == 1)
    }

    @Test func severalKeysAreAKeysLensSelectionOnThePlainBoard() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        session.select(keys: [13, 14])
        model.click(key: 15, .toggle)
        #expect(model.selectedKeyCount == 3)
        // Esc keeps the anchor first, then deselects.
        model.escapeBoard()
        #expect(session.selection.keyIndices == [13])
        model.escapeBoard()
        #expect(session.selection.keyIndex == nil)

        session.select(keys: [13, 14])
        model.lens = .lighting
        #expect(session.selection.keyIndices == [13], "another lens keeps the anchor")
        model.click(key: 20, .toggle)
        #expect(session.selection.keyIndices == [20], "and clicks select one key")
        model.lens = .keys

        // A pick takes the click whatever the modifiers.
        var picked: [Int] = []
        model.boardPick = BoardPick(
            prompt: "",
            onPick: {
                picked.append($0); return false
            })
        model.click(key: 30, .toggle)
        #expect(picked == [30] && session.selection.keyIndices == [20])
        model.cancelBoardPick()

        session.select(keys: [13, 14])
        model.destination = .history
        #expect(model.selectedKeyCount == 0, "a page doesn't show them")
    }

    @Test func thePickerAssignsToEverySelectedKeyKeepingEachChord() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        session.setModifiers([.leftCommand], index: 13)
        session.select(keys: [13, 14, 15])
        model.openKeycodePicker(prefilled: "[")
        #expect(model.pickerTarget == "3 keys › Tap on Main")
        model.runHighlighted()
        #expect(session.layout.key(layer: 0, index: 13)?.tap == KeyAction(code: "KC_LBRC", modifiers: [.leftCommand]))
        #expect(session.layout.key(layer: 0, index: 14)?.tap == KeyAction(code: "KC_LBRC"))
        #expect(session.layout.key(layer: 0, index: 15)?.tap == KeyAction(code: "KC_LBRC"))
        #expect(session.selection.keyIndices == [13, 14, 15])
    }

    @Test func thePickersMacroRowGoesOnEverySelectedKey() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        session.newMacro()
        let draft = try #require(session.selection.macro)
        session.insertStep(MacroStep(code: "KC_K"), at: 0, in: draft)
        session.select(keys: [13, 14])
        model.openKeycodePicker()
        model.palette?.category = .macros
        let row = try #require(model.paletteItems.first)
        model.run(row)
        #expect(session.layout.macroDrafts.isEmpty)
        #expect([13, 14].allSatisfy { session.layout.key(layer: 0, index: $0)?.tap?.macro?.steps == [MacroStep(code: "KC_K")] })
    }
}
