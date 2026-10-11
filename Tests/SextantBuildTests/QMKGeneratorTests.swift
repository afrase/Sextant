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

    /// The serial rule (application, ADR 0019) and the generator's serial check (ADR 0020) must agree.
    @Test func buildsWithASextantIdentity() throws {
        let layout = try userLayout()
        var edited = layout
        edited.updateKey(layer: 0, index: 1) { $0 = Key("KC_Q") }
        let identity = FirmwareIdentity(layout: edited, libraryID: UUID(), importedLayout: layout)
        #expect(identity.serial.hasPrefix("sx-"))
        let source = try QMKGenerator().generate(edited, identity: identity)
        #expect(source.files["config.h"]?.contains("#define SERIAL_NUMBER \"\(identity.serial)\"") == true)
        let unchanged = FirmwareIdentity(layout: layout, libraryID: UUID(), importedLayout: layout)
        #expect(unchanged.serial == "KlgM7/40xJ7M")
        #expect(throws: Never.self) { try QMKGenerator().generate(layout, identity: unchanged) }
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

    /// A layout switched to another Navigator (ADR 0035) gets that module's firmware lines, as Oryx writes them for the
    /// user's trackpad (KlgM7) and e5Rrr's trackball (less what e5Rrr's own options add, and with the pinned firmware's
    /// trackball module), and none with no Navigator.
    @Test func switchingTheNavigatorSwitchesItsFirmware() throws {
        func oryx(_ zip: String) throws -> [String: String] {
            try QMKGeneratorGoldenTests.unzipSources(QMKGeneratorGoldenTests.examples.appending(path: "sources/\(zip)"))
        }
        func lines(_ text: String?) -> [String] { (text ?? "").components(separatedBy: "\n") }
        func navigatorRules(_ text: String?) -> [String] {
            lines(text).filter { $0.hasPrefix("POINTING_DEVICE") || $0.hasPrefix("PRECISION_TRACKPAD") }
        }
        let user = try oryx("KlgM7-40xJ7M-source.zip"), e5Rrr = try oryx("e5Rrr-source.zip")
        let e5Config = lines(e5Rrr["config.h"])
        let start = try #require(e5Config.firstIndex(of: "#define WHEEL_EXTENDED_SUPPORT"))
        let end = try #require(e5Config.firstIndex(of: "#define NAVIGATOR_SCROLL_DIVIDER 75"))
        let trackballConfig = e5Config[start...end].filter { !$0.contains("CPI") }  // e5Rrr sets a sensitivity
        #expect(trackballConfig.count == 6)

        var layout = try userLayout()
        var files = try QMKGenerator().generate(layout, identity: identity).files
        #expect(navigatorRules(files["rules.mk"]) == navigatorRules(user["rules.mk"]) && navigatorRules(user["rules.mk"]).count == 2)

        layout.navigator?.side = .left  // like e5Rrr's; the firmware has nothing per side
        layout.setNavigator(.trackball)
        files = try QMKGenerator().generate(layout, identity: identity).files
        // e5Rrr's `POINTING_DEVICE_DRIVER = navigator_trackball` is the module's job now (see the golden allowances).
        #expect(navigatorRules(files["rules.mk"]) == navigatorRules(e5Rrr["rules.mk"]).filter { !$0.contains("DRIVER") })
        #expect(lines(files["config.h"]).joined(separator: "\n").contains(trackballConfig.joined(separator: "\n")))
        #expect(files["config.h"]?.contains("AUTO_MOUSE") == false)
        #expect(
            files["keymap.json"]?.contains("\"zsa/navigator_trackball\"") == true && files["keymap.json"]?.contains("trackpad") == false)

        layout.setNavigator(nil)
        files = try QMKGenerator().generate(layout, identity: identity).files
        #expect(navigatorRules(files["rules.mk"]).isEmpty && files["config.h"]?.contains("NAVIGATOR") == false)
        #expect(files["keymap.json"]?.contains("navigator") == false && files["keymap.c"]?.contains("navigator") == false)
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
        // SS_DELAY() stalls the keyboard for its whole pause: Oryx's 0...5000 ms only.
        for delay in [5000, 5001, 2_000_000_000, -1] {
            let pause = Macro(steps: [MacroStep(code: "KC_A", delay: delay)])
            layout.updateKey(layer: 0, index: 1) { $0 = Key(tap: KeyAction(code: "KC_NO", macro: pause)) }
            if delay == 5000 {
                _ = try QMKGenerator().generate(layout, identity: identity)
            } else {
                #expect(throws: GeneratorError.self, "\(delay)") { try QMKGenerator().generate(layout, identity: identity) }
            }
        }
        layout = clean
        layout.settings["rgbTimeout"] = .number(1e15)
        #expect(throws: GeneratorError.self) { try QMKGenerator().generate(layout, identity: identity) }
        layout = clean
        layout.updateKey(layer: 0, index: 24) { $0.tappingTerm = .min }
        #expect(throws: GeneratorError.self) { try QMKGenerator().generate(layout, identity: identity) }
        // zsa/oryx's version reply holds 30 serial characters.
        let long = FirmwareIdentity(serial: String(repeating: "a", count: 31))
        #expect(throws: GeneratorError.unsupported("the firmware serial “\(long.serial)”", nil)) {
            try QMKGenerator().generate(clean, identity: long)
        }
        _ = try QMKGenerator().generate(clean, identity: FirmwareIdentity(serial: String(repeating: "a", count: 30)))
        // LM() keeps 4 bits of the layer.
        layout = clean
        layout.layers += (layout.layers.count...16).map { .transparent(title: "\($0)") }
        layout.updateKey(layer: 0, index: 1) { $0 = Key(tap: KeyAction(code: "LM", layer: 16, modifiers: .leftShift)) }
        #expect(throws: GeneratorError.self) { try QMKGenerator().generate(layout, identity: identity) }
        layout.updateKey(layer: 0, index: 1) { $0 = Key(tap: KeyAction(code: "LM", layer: 15, modifiers: .leftShift)) }
        _ = try QMKGenerator().generate(layout, identity: identity)
        // Navigator options feed C defines too.
        for (id, value) in [("automouseTime", 0.0), ("automouseThreshold", 101)] {
            layout = clean
            layout.navigator?.options[id] = .number(value)
            #expect(throws: GeneratorError.self, "\(id) \(value)") { try QMKGenerator().generate(layout, identity: identity) }
        }
        layout = clean
        layout.automouseLayer = 40
        #expect(throws: GeneratorError.self) { try QMKGenerator().generate(layout, identity: identity) }
    }

    /// Catalog keys the generator would otherwise write as undeclared or dead keys.
    @Test func refusesCatalogKeysTheFirmwareWouldntDefineOrRun() throws {
        let clean = try userLayout()
        for code in ["MAC_SPOTLIGHT", "MAC_MISSION_CONTROL", "ORYX_SL_TOGG", "SC_LSPO", "KC_LSPO", "AS_TOGG"] {
            var layout = clean
            layout.updateKey(layer: 0, index: 1) { $0 = Key(code) }
            #expect(throws: GeneratorError.self, "\(code)") { try QMKGenerator().generate(layout, identity: identity) }
        }
        var layout = clean
        layout.settings["autoshift"] = .bool(true)
        layout.updateKey(layer: 0, index: 1) { $0 = Key("AS_TOGG") }
        #expect(try QMKGenerator().generate(layout, identity: identity).files["rules.mk"]?.contains("AUTO_SHIFT_ENABLE = yes") == true)
        layout = clean
        layout.updateKey(layer: 0, index: 1) { $0 = Key("KC_MS_DBL_CLICK") }
        #expect(try QMKGenerator().generate(layout, identity: identity).files["keymap.json"]?.contains("\"zsa/doubleclick\"") == true)
    }

    /// `ALL_T`/`MEH_T` are function-like macros; alone, Hyper and Meh are `KC_HYPR` and `KC_MEH`.
    @Test func writesALoneHyperOrMehAsItsKeycode() throws {
        var layout = try userLayout()
        layout.updateKey(layer: 0, index: 1) { $0 = Key(tap: .code("ALL_T")) }
        layout.updateKey(layer: 0, index: 2) { $0 = Key(hold: .code("KC_MEH")) }
        layout.combos = [Combo(keyIndices: [1, 2], layer: 0, output: .code("HYPR_T"))]
        let source = try QMKGenerator().generate(layout, identity: identity)
        let keymap = try #require(source.files["keymap.c"])
        #expect(keymap.contains("KC_HYPR, KC_MEH,"))
        #expect(keymap.contains("COMBO(combo0, KC_HYPR)"))
        #expect(!keymap.contains(/(ALL|MEH|HYPR)_T[^(]/))
    }
}
