import Foundation
import SextantApplication
import SextantDomain
import Testing

@testable import SextantBuild

/// What the golden tests don't cover: the source map, and refusing what the generator can't express.
struct QMKGeneratorTests {
    let identity = FirmwareIdentity(serial: "KlgM7/40xJ7M")

    func userLayout() throws -> KeyboardLayout {
        try KeyboardLayout(oryxJSON: Data(contentsOf: QMKGeneratorGoldenTests.examples.appending(path: "my-layout-KlgM7-full.json")))
    }

    @Test func sourceMapPointsKeymapLinesAtKeys() throws {
        let source = try QMKGenerator().generate(try userLayout(), identity: identity)
        let lines = try #require(source.files["keymap.c"]).components(separatedBy: "\n")
        func key(ofLineContaining text: String, after start: String = "") -> KeyRef? {
            let from = lines.firstIndex { !start.isEmpty && $0.contains(start) } ?? 0
            return lines[from...].firstIndex { $0.contains(text) }.flatMap { source.sourceMap[$0 + 1] }
        }
        #expect(key(ofLineContaining: "LT(2, KC_SPACE)") == KeyRef(layer: 0, index: 51, slot: nil))
        #expect(key(ofLineContaining: "    QK_BOOT") == KeyRef(layer: 2, index: 31, slot: .tap))
        #expect(key(ofLineContaining: "register_code16(KC_EQUAL)", after: "case DUAL_FUNC_0") == KeyRef(layer: 0, index: 0, slot: .tap))
        #expect(key(ofLineContaining: "register_code16(KC_ESCAPE)", after: "case DUAL_FUNC_0") == KeyRef(layer: 0, index: 0, slot: .hold))
    }

    @Test func refusesSettingsAndNavigatorOptionsItCantWrite() throws {
        var layout = try userLayout()
        layout.settings["retroTapping"] = .bool(true)
        #expect(throws: GeneratorError.self) { try QMKGenerator().generate(layout, identity: identity) }
        layout.settings["retroTapping"] = .bool(false)  // the default writes nothing
        _ = try QMKGenerator().generate(layout, identity: identity)
        layout.navigator?.options["invertScrollX"] = .bool(true)
        #expect(throws: GeneratorError.unsupported("the Navigator's “invertScrollX” option", nil)) {
            try QMKGenerator().generate(layout, identity: identity)
        }
    }

    @Test func refusesKeysItCantExpress() throws {
        var layout = try userLayout()
        let macro = KeyAction(code: "KC_TRANSPARENT", macro: Macro(steps: [MacroStep(code: "KC_A")]))
        layout.updateKey(layer: 1, index: 3) { $0 = Key(tap: .code("KC_A"), doubleTap: macro) }
        #expect(
            throws: GeneratorError.unsupported(
                "a macro as part of a dual-function or tap-dance key", KeyRef(layer: 1, index: 3, slot: .doubleTap))
        ) {
            try QMKGenerator().generate(layout, identity: identity)
        }
        // A layer-tap to a missing layer is refused like a plain layer key.
        layout.updateKey(layer: 1, index: 3) { $0 = Key(tap: .code("KC_A"), hold: .momentary(7)) }
        #expect(throws: GeneratorError.unsupported("a layer key for a layer that doesn't exist", KeyRef(layer: 1, index: 3, slot: .hold))) {
            try QMKGenerator().generate(layout, identity: identity)
        }
    }

    /// Imported layouts are untrusted: their text is pasted into C, and their numbers feed arithmetic.
    @Test func refusesInputThatWouldInjectCOrOverflow() throws {
        let clean = try userLayout()
        var layout = clean
        layout.updateKey(layer: 0, index: 1) { $0 = Key("KC_A\n#include \"/etc/passwd\"") }
        #expect(throws: GeneratorError.self) { try QMKGenerator().generate(layout, identity: identity) }
        layout = clean
        layout.updateKey(layer: 0, index: 1) { $0 = Key(tap: KeyAction(code: "KC_NO", macro: Macro(steps: [MacroStep(code: "A);x(")]))) }
        #expect(throws: GeneratorError.self) { try QMKGenerator().generate(layout, identity: identity) }
        #expect(throws: GeneratorError.self) { try QMKGenerator().generate(clean, identity: FirmwareIdentity(serial: "a\"\n#include")) }
        layout = clean
        layout.settings["rgbTimeout"] = .number(1e15)
        #expect(throws: GeneratorError.self) { try QMKGenerator().generate(layout, identity: identity) }
        layout = clean
        layout.updateKey(layer: 0, index: 24) { $0.tappingTerm = .min }
        #expect(throws: GeneratorError.self) { try QMKGenerator().generate(layout, identity: identity) }
    }
}
