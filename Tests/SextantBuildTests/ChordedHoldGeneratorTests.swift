import Foundation
import SextantApplication
import SextantDomain
import Testing

@testable import SextantBuild

/// The key editor's modifier holds (ADR 0027): one modifier keycode chorded with the rest, built as a dual-function key
/// or a tap-dance hold that presses every modifier as a real modifier: `register_code16` would make all but one weak,
/// and QMK clears weak modifiers at the next key press.
struct ChordedHoldGeneratorTests {
    let identity = FirmwareIdentity(serial: "KlgM7/40xJ7M")

    func keymap(with key: Key) throws -> [String] {
        var layout = try KeyboardLayout(
            oryxJSON: Data(contentsOf: QMKGeneratorGoldenTests.examples.appending(path: "my-layout-KlgM7-full.json")))
        layout.updateKey(layer: 0, index: 0) { $0 = key }
        let source = try QMKGenerator().generate(layout, identity: identity)
        return try #require(source.files["keymap.c"]).components(separatedBy: "\n")
    }

    @Test func chordedHoldIsADualFunctionKey() throws {
        let lines = try keymap(with: Key(tap: .code("KC_A"), hold: .code("KC_LEFT_CTRL", modifiers: [.leftShift])))
        let start = try #require(lines.firstIndex { $0.contains("case DUAL_FUNC_0:") })
        let block = lines[start...].prefix(14).joined(separator: "\n")
        #expect(block.contains("register_code16(KC_A);"))
        #expect(block.contains("register_mods(MOD_BIT(KC_LEFT_CTRL) | MOD_BIT(KC_LEFT_SHIFT));"))
        #expect(block.contains("unregister_mods(MOD_BIT(KC_LEFT_CTRL) | MOD_BIT(KC_LEFT_SHIFT));"))
    }

    /// Hyper as the editor writes it (chorded) builds in a tap dance.
    @Test func chordedHyperBuildsInATapDance() throws {
        let hyper = KeyAction.code("KC_LEFT_CTRL", modifiers: [.leftShift, .leftOption, .leftCommand])
        let lines = try keymap(with: Key(tap: .code("KC_A"), doubleTap: .code("KC_B"), tapHold: hyper))
        let all = "MOD_BIT(KC_LEFT_CTRL) | MOD_BIT(KC_LEFT_SHIFT) | MOD_BIT(KC_LEFT_ALT) | MOD_BIT(KC_LEFT_GUI)"
        #expect(lines.contains { $0.contains("register_mods(\(all));") })
    }

    /// An imported Oryx Hyper or Meh hold still builds once the tap gets a chord or a double tap.
    @Test func importedHyperAndMehHoldsBuildBesideAnyTap() throws {
        let hyper = try keymap(with: Key(tap: .code("KC_A", modifiers: [.leftShift]), hold: .code("ALL_T")))
        let all = "MOD_BIT(KC_LEFT_CTRL) | MOD_BIT(KC_LEFT_SHIFT) | MOD_BIT(KC_LEFT_ALT) | MOD_BIT(KC_LEFT_GUI)"
        #expect(hyper.contains { $0.contains("register_mods(\(all));") })
        let meh = try keymap(with: Key(tap: .code("KC_A"), hold: .code("MEH_T"), doubleTap: .code("KC_B")))
        #expect(meh.contains { $0.contains("unregister_mods(MOD_BIT(KC_LEFT_CTRL) | MOD_BIT(KC_LEFT_SHIFT) | MOD_BIT(KC_LEFT_ALT));") })
        #expect(!meh.contains { $0.contains("KC_MEH") })
    }

    /// Sides stay exact (QMK's 5-bit `MOD_*` masks can't mix them), and a bare modifier stays as Oryx writes it.
    @Test func rightSideChordsKeepTheirSide() throws {
        let lines = try keymap(with: Key(tap: .code("KC_A"), hold: .code("KC_RIGHT_ALT", modifiers: [.leftShift])))
        #expect(lines.contains { $0.contains("register_mods(MOD_BIT(KC_LEFT_SHIFT) | MOD_BIT(KC_RIGHT_ALT));") })
        #expect(QMKCodes.statements(.code("KC_LEFT_CTRL"))?.press == "register_code16(KC_LEFT_CTRL);")
    }
}
