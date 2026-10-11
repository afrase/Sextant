import Foundation
import SextantApplication
import SextantDomain
import SwiftUI
import Testing

@testable import SextantUI

@MainActor
struct KeyInspectorTests {
    /// Spec §5.2: the Hold editor reads what a slot holds from the action Oryx stores.
    @Test func holdModeFollowsTheStoredAction() {
        #expect(HoldMode(nil) == .nothing)
        #expect(HoldMode(.code("KC_LEFT_ALT")) == .modifier)
        #expect(HoldMode(KeyAction(code: "MEH_T")) == .modifier)
        #expect(HoldMode(.momentary(1)) == .layer)
        #expect(HoldMode(.moveTo(0)) == .layer)
        #expect(HoldMode(.code("KC_ESCAPE")) == .key)
        #expect(HoldMode(KeyAction(code: "KC_LEFT_ALT", macro: Macro(steps: [MacroStep(code: "KC_A")]))) == .key)
    }

    /// Several modifiers are one keycode chorded with the rest; Hyper and Meh are Oryx's `ALL_T` and `MEH_T`.
    @Test func modifierHoldsRoundTrip() {
        #expect(KeyAction.holding([.leftOption]) == .code("KC_LEFT_ALT"))
        #expect(KeyAction.holding(.hyper) == KeyAction(code: "ALL_T"))
        #expect(KeyAction.holding(.meh) == KeyAction(code: "MEH_T"))
        #expect(KeyAction.holding([.leftControl, .leftShift]) == .code("KC_LEFT_CTRL", modifiers: [.leftShift]))
        #expect(KeyAction.holding([]) == nil, "no modifiers holds nothing")
        for mods: Modifiers in [[.rightCommand], [.leftShift, .leftCommand], .hyper, .meh, [.rightControl, .rightOption]] {
            #expect(KeyAction.holding(mods)?.heldModifiers == mods)
        }
        // The QMK row shows every held modifier, not just the keycode's.
        let key = Key(tap: .code("KC_A"), hold: .holding([.leftControl, .leftShift]))
        #expect(Legends.qmkExpression(for: key) == "MT(MOD_LCTL | MOD_LSFT, KC_A)")
    }

    @Test func modifiersMoveSides() {
        let mods: Modifiers = [.leftControl, .leftShift]
        #expect(mods.onSide(right: true) == [.rightControl, .rightShift])
        #expect(mods.onSide(right: true).onSide(right: false) == mods)
        #expect(mods.onSide(right: true).isRightSided && !mods.isRightSided && !Modifiers().isRightSided)
        #expect(Modifiers([.leftOption, .rightOption]).onSide(right: false) == [.leftOption])
    }

    /// Spec §5.3: a warning for the key's own layer, or a lower layer the key's layer would hide.
    @Test func layerWarnings() async throws {
        let layout = try #require(try await openUserLayout().session).layout
        #expect(KeyText.layerWarning(code: "MO", target: 1, own: 1, layout: layout) != nil)
        #expect(KeyText.layerWarning(code: "MO", target: 1, own: 2, layout: layout)?.contains("Sym+Num is below Brd+Sys") == true)
        #expect(KeyText.layerWarning(code: "TO", target: 0, own: 2, layout: layout) == nil, "Go to turns the other layers off")
        #expect(KeyText.layerWarning(code: "TG", target: 2, own: 0, layout: layout) == nil)
    }

    @Test func summaryAndInheritanceSentences() async throws {
        let session = try #require(try await openUserLayout().session)
        let layout = session.layout
        let names = layout.layerNames
        let key = { (layer: Int, index: Int) in try #require(layout.key(layer: layer, index: index)) }
        #expect(KeyText.summary(try key(0, 24), layerNames: names) == "Tap sends Return. Hold activates Sym+Num (MO(1)).")
        #expect(KeyText.summary(try key(0, 19), layerNames: names).hasSuffix("Hold for Left Option."))
        #expect(KeyText.summary(Key(hold: .holding(.hyper)), layerNames: names) == "Hold for Hyper.")
        #expect(KeyText.summary(Key(tap: .toggle(2)), layerNames: names) == "Tap: Toggle Brd+Sys (TG(2)).")
        let inherited = Legends.legend(layout: layout, layer: 1, index: 19)
        #expect(KeyText.inheritance(inherited, layout: layout, layer: 1) == "Transparent on Sym+Num. Acts as Z (hold ⌥) from Main.")
    }

    /// Spec §5.5: a drag swaps two keys, ⌥-drag copies, each one undo step; a drag that misses does nothing.
    @Test func dragSwapsOrCopiesKeys() async throws {
        let session = try #require(try await openUserLayout().session)
        let undo = UndoManager()
        undo.groupsByEvent = false
        session.undoManager = undo
        let board = session.geometry.layout(keySize: 50, spacing: 5)
        let (z, enter) = (board.frame(19).center, board.frame(24).center)  // 24 is a rotated thumb
        let before = session.layout
        let (a, b) = (try #require(before.key(layer: 0, index: 19)), try #require(before.key(layer: 0, index: 24)))

        undo.beginUndoGrouping()
        #expect(session.dragKey(from: z, to: enter, on: board, copy: false))
        undo.endUndoGrouping()
        #expect(session.layout.key(layer: 0, index: 24) == a && session.layout.key(layer: 0, index: 19) == b)
        #expect(session.selection.keyIndex == 24 && undo.undoActionName == "Swap Keys")
        undo.undo()
        #expect(session.layout == before)

        undo.beginUndoGrouping()
        #expect(session.dragKey(from: z, to: enter, on: board, copy: true))
        undo.endUndoGrouping()
        #expect(session.layout.key(layer: 0, index: 24) == a && session.layout.key(layer: 0, index: 19) == a)
        #expect(undo.undoActionName == "Copy Key")

        let copied = session.layout
        #expect(!session.dragKey(from: z, to: CGPoint(x: -10, y: -10), on: board, copy: false), "off the board")
        #expect(!session.dragKey(from: z, to: CGPoint(x: z.x + 3, y: z.y), on: board, copy: false), "the same key")
        #expect(session.layout == copied)
    }

    @Test func pickedColoursRoundToStoredHex() {
        let picked = HexColor(Color(.sRGB, red: 0.5004, green: 0.2, blue: 1, opacity: 1))
        #expect(picked == HexColor(hex: "#8033FF"))
    }
}
