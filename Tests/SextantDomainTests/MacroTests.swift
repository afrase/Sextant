import Foundation
import Testing

@testable import SextantDomain

/// The macro library and its edits (spec §6.3, ADR 0042).
struct MacroTests {
    @Test func theLibraryListsKeysThenCombosThenDrafts() throws {
        var jr = try Fixtures.layout("voyager-JRGQm.json")
        var macros = jr.macros
        #expect(macros.count == 67, "66 keys and 1 combo")
        #expect(macros.first?.locator == .key(KeyRef(layer: 2, index: 32, slot: .tap)))
        #expect(macros.first?.macro.steps.first == MacroStep(code: "KC_1", modifiers: [.leftControl, .leftCommand], delay: 100))
        #expect(macros.filter { if case .combo = $0.locator { true } else { false } }.count == 1)
        let draft = jr.addMacroDraft(Macro(name: "Sig", steps: [MacroStep(code: "KC_S")]), id: "d1")
        macros = jr.macros
        #expect(draft == .draft("d1") && macros.last?.locator == draft && macros.count == 68)
        for entry in macros { #expect(jr.macro(at: entry.locator) == entry.macro) }

        let xl = try Fixtures.layout("voyager-XlrR4.json")
        #expect(xl.macros.count == 6)
        #expect(
            xl.macros.filter(\.macro.holdsOption).map(\.locator) == [6, 12, 44, 45].map { .key(KeyRef(layer: 3, index: $0, slot: .tap)) })
    }

    @Test func assigningPutsTheMacroOnATapAndClearsTheRest() throws {
        var layout = try Fixtures.layout()
        layout.updateKey(layer: 0, index: 19) { $0 = Key(tap: .code("KC_Z"), hold: .code("KC_LEFT_ALT"), doubleTap: .code("KC_X")) }
        let draft = layout.addMacroDraft(Macro(steps: [MacroStep(code: "KC_K")]), id: "d")
        let assigned = layout.assignMacro(at: draft, toKey: 0, index: 19)
        let placed = try #require(assigned)
        #expect(placed == .key(KeyRef(layer: 0, index: 19, slot: .tap)))
        let key = try #require(layout.key(layer: 0, index: 19))
        #expect(key.tap?.macro?.steps == [MacroStep(code: "KC_K")] && key.tap?.code == "KC_TRANSPARENT")
        #expect(key.hold == nil && key.doubleTap == nil && key.kind == .macro)
        #expect(layout.macroDrafts.isEmpty, "a draft moves onto the key")

        // A macro already on a key is copied, as Oryx keeps a copy per key.
        let copied = layout.assignMacro(at: placed, toKey: 1, index: 0)
        #expect(copied != nil && layout.macro(at: placed) == layout.macro(at: .key(KeyRef(layer: 1, index: 0, slot: .tap))))
        let missing = (layout.assignMacro(at: .draft("gone"), toKey: 0, index: 1), layout.assignMacro(at: placed, toKey: 0, index: 99))
        #expect(missing.0 == nil && missing.1 == nil)
    }

    @Test func unassigningAndRemovingEmptyTheSlot() throws {
        var layout = try Fixtures.layout("voyager-JRGQm.json")
        let first = try #require(layout.macros.first)
        let unassigned = layout.unassignMacro(at: first.locator, draftID: "x")
        let draft = try #require(unassigned)
        var named = first.macro
        named.name = "Teams Cam"
        #expect(draft == .draft("x") && layout.macro(at: draft) == named, "an unnamed macro takes its key's label")
        let emptied = try #require(layout.key(layer: 2, index: 32))
        #expect(emptied.tap == .transparent && emptied.filledSlots == [.tap], "a key left with nothing is transparent")
        #expect(emptied.customLabel == "Teams Cam", "and keeps its label")
        let again = layout.unassignMacro(at: draft)
        #expect(again == nil, "a draft is already off the keys")
        layout.removeMacro(at: draft)
        #expect(layout.macroDrafts.isEmpty)

        let combo = try #require(layout.macros.first { if case .combo = $0.locator { true } else { false } })
        layout.removeMacro(at: combo.locator)
        #expect(LayoutIssues.check(layout).contains { $0.kind == .emptyCombo }, "a combo without its macro is empty")
    }

    @Test func stepEditsStayInBounds() {
        var macro = Macro(steps: ["KC_A", "KC_B", "KC_C"].map { MacroStep(code: $0) })
        macro.moveStep(from: 0, to: 3)
        #expect(macro.steps.map(\.code) == ["KC_B", "KC_C", "KC_A"])
        macro.moveStep(from: 2, to: 0)
        #expect(macro.steps.map(\.code) == ["KC_A", "KC_B", "KC_C"])
        macro.moveStep(from: 5, to: 0)
        macro.moveStep(from: 0, to: 9)
        macro.duplicateStep(at: 1)
        macro.removeStep(at: 7)
        #expect(macro.steps.map(\.code) == ["KC_A", "KC_B", "KC_B", "KC_C"])
        macro.insertStep(MacroStep(code: "KC_Z"), at: 99)
        macro.insertStep(MacroStep(code: "KC_Y"), at: -3)
        #expect(macro.steps.first?.code == "KC_Y" && macro.steps.last?.code == "KC_Z")
        macro.setDelay(9000, at: 0)
        macro.setDelay(-5, at: 1)
        #expect(macro.steps[0].delay == 5000 && macro.steps[1].delay == 0)
    }

    /// `SEND_STRING` types a step by its `X_` name: keycodes have one, layer keys, `QK_` and locale codes don't.
    @Test func onlyKeycodesWithAnXNameAreSteps() throws {
        for code in ["KC_A", "KC_1", "KC_SPACE", "KC_ENTER", "KC_KP_1", "KC_LEFT_SHIFT", "KC_AUDIO_VOL_UP", "KC_MS_BTN1", "KC_F24"] {
            #expect(MacroStep.canType(code), "\(code)")
        }
        for code in ["MO", "TG", "QK_BOOT", "KC_TRANSPARENT", "KC_NO", "UK_PND", "RGB_TOG", "KC_MAC_COPY", "X_A", "KC_"] {
            #expect(!MacroStep.canType(code), "\(code)")
        }
        // Oryx compiled every macro in the fixtures, so all of their steps type.
        for file in Fixtures.allLayoutFiles {
            for entry in try Fixtures.layout(file).macros {
                for step in entry.macro.steps { #expect(MacroStep.canType(step.code), "\(file): \(step.code)") }
            }
        }
    }

    @Test func stepsThatCannotTypeRaiseAnIssueOnTheirKey() throws {
        for file in Fixtures.allLayoutFiles {
            #expect(
                !LayoutIssues.check(try Fixtures.layout(file)).contains { if case .macroStepNotTypable = $0.kind { true } else { false } })
        }
        var layout = try Fixtures.layout("voyager-JRGQm.json")
        let first = try #require(layout.macros.first)
        layout.updateMacro(at: first.locator) { $0.steps[1].code = "MO" }
        let draft = layout.addMacroDraft(Macro(steps: [MacroStep(code: "QK_BOOT")]))
        layout.updateMacro(at: draft) { $0.steps.append(MacroStep(code: "KC_FOO")) }
        let issues = LayoutIssues.check(layout)
        let steps = issues.filter { if case .macroStepNotTypable = $0.kind { true } else { false } }
        #expect(steps.map(\.kind) == [.macroStepNotTypable(step: 1, code: "MO")], "drafts never reach the firmware")
        #expect(steps.first?.key == KeyRef(layer: 2, index: 32, slot: .tap) && steps.first?.severity == .error)
        #expect(!issues.contains { $0.kind == .unknownKeycode("KC_FOO") }, "nor do their unknown codes count")
    }

    /// Drafts are written only when there are some, so every existing layout encodes exactly as before.
    @Test func draftsRoundTripAndAreLeftOutWhenEmpty() throws {
        var layout = try Fixtures.layout("voyager-XlrR4.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let plain = try encoder.encode(layout)
        #expect(String(bytes: plain, encoding: .utf8)?.contains("macroDrafts") == false)
        layout.addMacroDraft(Macro(name: "Hi", steps: [MacroStep(code: "KC_H", modifiers: [.leftShift], delay: 30)], endsWithEnter: true))
        let decoded = try KeyboardLayout(oryxJSON: encoder.encode(layout))
        #expect(decoded == layout && decoded.macroDrafts.count == 1)
        layout.macroDrafts = []
        #expect(try encoder.encode(layout) == plain)
    }
}
