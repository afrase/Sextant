import Foundation
import SextantDomain
import Testing

struct LayoutIssuesTests {
    /// A three-layer layout of transparent keys whose layer 1 is reached from Space.
    func layout() -> KeyboardLayout {
        var layout = KeyboardLayout(
            title: "Test", layers: [.transparent(title: "Base"), .transparent(title: "One"), .transparent(title: "Two")])
        layout.updateKey(layer: 0, index: 51) { $0 = Key(tap: .code("KC_SPACE"), hold: .momentary(1)) }
        layout.updateKey(layer: 1, index: 0) { $0 = Key(tap: .moveTo(2)) }
        return layout
    }

    /// Oryx built every example, so none has an error; unreachable layers are only warnings.
    @Test(arguments: Fixtures.allLayoutFiles)
    func oryxExamplesHaveNoErrors(file: String) throws {
        let issues = LayoutIssues.check(try Fixtures.layout(file))
        #expect(!issues.contains { $0.severity == .error }, "\(issues)")
    }

    @Test func aCleanLayoutHasNoIssues() {
        #expect(LayoutIssues.check(layout()).isEmpty)
    }

    @Test func findsEachKindErrorsFirstThenInKeyOrder() {
        var layout = layout()
        layout.updateKey(layer: 1, index: 0) { $0 = Key(tap: .code("KC_LBRACKETT")) }  // layer 2 is now unreachable
        layout.updateKey(layer: 0, index: 3) { $0 = Key(tap: .momentary(9)) }
        let long = Macro(steps: Array(repeating: MacroStep(code: "KC_A"), count: 25))
        layout.updateKey(layer: 1, index: 7) { $0 = Key(tap: KeyAction(code: "KC_TRANSPARENT", macro: long)) }
        layout.combos = [Combo(keyIndices: [1], output: .code("KC_ESCAPE"))]

        let issues = LayoutIssues.check(layout)
        #expect(
            issues.map(\.kind) == [
                .missingLayer(9), .unknownKeycode("KC_LBRACKETT"), .emptyCombo, .macroTooLong(steps: 25), .unreachableLayer(2),
            ])
        #expect(issues.map(\.severity) == [.error, .error, .error, .warning, .warning])
        #expect(issues[1].key == KeyRef(layer: 1, index: 0, slot: .tap))
        #expect(issues[0].key == KeyRef(layer: 0, index: 3, slot: .tap))
    }

    /// Combo issues carry the combo, so two broken combos are two issues.
    @Test func comboIssuesNameTheirCombo() {
        var layout = layout()
        layout.combos = [
            Combo(id: "a", keyIndices: [1], output: .code("KC_ESCAPE")),
            Combo(id: "b", keyIndices: [2, 3], output: .code("KC_NOPE")),
            Combo(id: "c", keyIndices: [4], output: .code("KC_TAB")),
        ]
        // Not the member checks (ComboTests): this layout's keys 2 and 3 are transparent neighbors.
        let issues = LayoutIssues.check(layout).filter { issue in
            switch issue.kind {
            case .comboKeyTransparent, .rollingNeighbors: false
            default: true
            }
        }
        #expect(issues.map(\.kind) == [.emptyCombo, .unknownKeycode("KC_NOPE"), .emptyCombo])
        #expect(issues.map(\.combo) == ["a", "b", "c"] && issues.allSatisfy { $0.key == nil })
        #expect(Set(issues.map(\.id)).count == 3)
    }

    /// Spec §6.5: a dance slot the firmware can't run is flagged on that slot, before any build.
    @Test func flagsDanceSlotsThatCantRun() {
        var layout = layout()
        let macro = KeyAction(code: "KC_TRANSPARENT", macro: Macro(steps: [MacroStep(code: "KC_A")]))
        layout.updateKey(layer: 0, index: 1) { $0 = Key(tap: .code("KC_A"), doubleTap: macro) }
        layout.updateKey(layer: 0, index: 2) {
            $0 = Key(tap: .code("KC_A"), hold: .toggle(1), tapHold: .setColor(HexColor(red: 1, green: 0, blue: 0)))
        }
        layout.updateKey(layer: 0, index: 3) { $0 = Key(tap: .momentary(1), doubleTap: .code("QK_BOOT")) }  // a layer isn't a tap
        layout.updateKey(layer: 0, index: 4) { $0 = Key(doubleTap: KeyAction(code: "OSM", modifiers: .leftShift)) }
        // These run: keys, chorded and lone modifiers, MO and TO, and a locale tap.
        layout.updateKey(layer: 0, index: 5) {
            $0 = Key(
                tap: .code("UK_PND"), hold: .code("KC_LEFT_CTRL", modifiers: .leftShift), doubleTap: .code("ALL_T"), tapHold: .moveTo(2))
        }
        layout.updateKey(layer: 0, index: 6) { $0 = Key(tap: .code("KC_A"), hold: .toggle(1)) }  // not a dance
        // Spelled with KC_, but only their own handlers run them: ZSA's module keys and Auto Shift's and Space Cadet's aliases.
        layout.updateKey(layer: 0, index: 7) { $0 = Key(tap: .code("KC_MS_DBL_CLICK"), doubleTap: .code("KC_MS_JIGGLER_TOGGLE")) }
        layout.updateKey(layer: 0, index: 8) { $0 = Key(tap: .code("KC_A"), doubleTap: .code("KC_ASTG"), tapHold: .code("KC_LSPO")) }

        let flagged = LayoutIssues.check(layout).filter { $0.kind == .notInTapDance }
        #expect(
            flagged.compactMap(\.key) == [
                KeyRef(layer: 0, index: 1, slot: .doubleTap), KeyRef(layer: 0, index: 2, slot: .hold),
                KeyRef(layer: 0, index: 2, slot: .tapHold),
                KeyRef(layer: 0, index: 3, slot: .tap), KeyRef(layer: 0, index: 3, slot: .doubleTap),
                KeyRef(layer: 0, index: 4, slot: .doubleTap),
                KeyRef(layer: 0, index: 7, slot: .tap), KeyRef(layer: 0, index: 7, slot: .doubleTap),
                KeyRef(layer: 0, index: 8, slot: .doubleTap), KeyRef(layer: 0, index: 8, slot: .tapHold),
            ])
        #expect(flagged.allSatisfy { $0.severity == .error })
    }

    /// The firmware drops a key's own term while per-key terms are off, so an imported one warns.
    @Test func warnsOfATappingTermThatPerKeyTermsIgnore() {
        var layout = layout()
        layout.updateKey(layer: 0, index: 51) { $0.tappingTerm = 250 }
        let issues = LayoutIssues.check(layout)
        #expect(issues.map(\.kind) == [.tappingTermIgnored] && issues.map(\.severity) == [.warning])
        #expect(issues.first?.key == KeyRef(layer: 0, index: 51))
        layout.settings["perKeyTappingTerm"] = .bool(true)
        #expect(LayoutIssues.check(layout).isEmpty)
    }

    /// Oryx built every example: no dance slot it couldn't run, no term it ignored.
    @Test(arguments: Fixtures.allLayoutFiles)
    func oryxExamplesRaiseNoDanceOrTermIssues(file: String) throws {
        let issues = LayoutIssues.check(try Fixtures.layout(file))
        #expect(!issues.contains { $0.kind == .notInTapDance || $0.kind == .tappingTermIgnored }, "\(issues)")
    }

    @Test func combosAndTheAutomouseLayerReachLayers() {
        var layout = layout()
        layout.updateKey(layer: 1, index: 0) { $0 = .transparent }
        #expect(LayoutIssues.check(layout).map(\.kind) == [.unreachableLayer(2)])
        layout.combos = [Combo(keyIndices: [1, 2], layer: 1, output: .toggle(2))]
        // Its keys raise member issues (ComboTests); the layer it toggles is reached.
        #expect(LayoutIssues.check(layout).allSatisfy { $0.combo != nil })
        layout.combos = []
        layout.automouseLayer = 2
        #expect(LayoutIssues.check(layout).map(\.kind) == [.unreachableLayer(2)], "no Navigator, no automouse")
        layout.navigator = NavigatorConfig(kind: .trackpad, side: .right)
        #expect(LayoutIssues.check(layout).isEmpty)
    }
}

struct FlashPathTests {
    /// The user's layout: hold Space (key 51) for Brd+Sys, then press key 31.
    @Test func findsTheUsersResetKey() throws {
        let path = try #require(FlashPath.find(in: try Fixtures.layout()))
        #expect(path.holds == [KeyRef(layer: 0, index: 51, slot: .hold)])
        #expect(path.reset == KeyRef(layer: 2, index: 31, slot: .tap))
    }

    @Test func followsChainsOfHoldsAndPrefersTheShortest() {
        var layout = KeyboardLayout(
            title: "T", layers: [.transparent(title: "0"), .transparent(title: "1"), .transparent(title: "2"), .transparent(title: "3")])
        #expect(FlashPath.find(in: layout) == nil)
        layout.updateKey(layer: 0, index: 24) { $0 = Key(tap: .momentary(1)) }
        layout.updateKey(layer: 1, index: 25) { $0 = Key(tap: .code("KC_A"), hold: .momentary(2)) }
        layout.updateKey(layer: 2, index: 5) { $0 = Key(tap: .code("QK_BOOT")) }
        #expect(
            FlashPath.find(in: layout)
                == FlashPath(
                    holds: [KeyRef(layer: 0, index: 24, slot: .tap), KeyRef(layer: 1, index: 25, slot: .hold)],
                    reset: KeyRef(layer: 2, index: 5, slot: .tap)))
        layout.updateKey(layer: 0, index: 50) { $0 = Key(tap: .momentary(3)) }
        layout.updateKey(layer: 3, index: 6) { $0 = Key(tap: .code("QK_BOOT")) }
        #expect(FlashPath.find(in: layout)?.holds == [KeyRef(layer: 0, index: 50, slot: .tap)])
    }

    @Test func aResetKeyUnderAHeldKeyCantBePressed() {
        var layout = KeyboardLayout(title: "T", layers: [.transparent(title: "0"), .transparent(title: "1")])
        layout.updateKey(layer: 0, index: 24) { $0 = Key(tap: .momentary(1)) }
        layout.updateKey(layer: 1, index: 24) { $0 = Key(tap: .code("QK_BOOT")) }
        #expect(FlashPath.find(in: layout) == nil)
        // A second thumb that also holds layer 1 frees key 24.
        layout.updateKey(layer: 0, index: 50) { $0 = Key(tap: .momentary(1)) }
        #expect(
            FlashPath.find(in: layout)
                == FlashPath(holds: [KeyRef(layer: 0, index: 50, slot: .tap)], reset: KeyRef(layer: 1, index: 24, slot: .tap)))
    }
}
