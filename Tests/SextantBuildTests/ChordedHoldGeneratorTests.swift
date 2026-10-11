import Foundation
import SextantApplication
import SextantDomain
import Testing

@testable import SextantBuild

/// The key editor's modifier holds (ADR 0027): one modifier keycode chorded with the rest, built as a dual-function key
/// or a tap-dance hold that presses every modifier.
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
        #expect(block.contains("register_code16(LSFT(KC_LEFT_CTRL));"))
        #expect(block.contains("unregister_code16(LSFT(KC_LEFT_CTRL));"))
    }

    /// Hyper as the editor writes it builds in a tap dance, where Oryx's `ALL_T` can't.
    @Test func chordedHyperBuildsInATapDance() throws {
        let hyper = KeyAction.code("KC_LEFT_CTRL", modifiers: [.leftShift, .leftOption, .leftCommand])
        let lines = try keymap(with: Key(tap: .code("KC_A"), doubleTap: .code("KC_B"), tapHold: hyper))
        #expect(lines.contains { $0.contains("register_code16(LALT(LGUI(LSFT(KC_LEFT_CTRL))))") })
    }
}
