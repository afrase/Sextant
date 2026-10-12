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
        let clean = try userLayout()
        for id in Self.stillRefused {
            let setting = try #require(SettingsCatalog.voyager.setting(id: id))
            var layout = clean
            layout.settings[id] = .bool(setting.defaultValue != .bool(true))
            #expect(throws: GeneratorError.unsupported("the “\(setting.title)” setting", nil)) {
                try QMKGenerator().generate(layout, identity: identity)
            }
            layout.settings[id] = setting.defaultValue  // the default writes nothing
            _ = try QMKGenerator().generate(layout, identity: identity)
        }
        var layout = clean
        layout.settings["debounce"] = .text("5")  // a value of the wrong type
        #expect(throws: GeneratorError.self) { try QMKGenerator().generate(layout, identity: identity) }
        layout = clean
        layout.navigator?.options["invertScrollX"] = .bool(true)
        #expect(throws: GeneratorError.unsupported("the Navigator's “invertScrollX” option", nil)) {
            try QMKGenerator().generate(layout, identity: identity)
        }
        layout = try Self.settingsLayout(.trackball)
        layout.navigator?.options["aimSpeed"] = .bool(true)  // a value of the wrong type
        #expect(throws: GeneratorError.unsupported("the Navigator's “aimSpeed” option", nil)) {
            try QMKGenerator().generate(layout, identity: identity)
        }
        // QMK's one-shot auto mouse has no idle timeout; the timeout is on whenever stored, and moot without one-shot.
        layout = try Self.settingsLayout(.trackball)
        layout.navigator?.options["oneShotAutoMouseTimeout"] = .number(10)
        _ = try QMKGenerator().generate(layout, identity: identity)
        layout.navigator?.options["oneShotAutoMouse"] = .bool(true)
        #expect(throws: GeneratorError.unsupported("the Navigator's “oneShotAutoMouseTimeout” option", nil)) {
            try QMKGenerator().generate(layout, identity: identity)
        }
        layout = try Self.settingsLayout(.trackball)
        layout.navigator?.options["aimLayers"] = .integers([1, 3])
        #expect(throws: GeneratorError.unsupported("the Navigator's “aimLayers” option", nil)) {
            try QMKGenerator().generate(layout, identity: identity)
        }
    }

    // MARK: Settings (ADR 0040)

    /// Changes to a layout's settings and the text they add to its firmware source.
    struct Mapping: Sendable, CustomTestStringConvertible {
        /// A Navigator option is tried on this Navigator only; a setting on the trackpad, and with both at once.
        var only: NavigatorConfig.Kind?
        var changes: [String: SettingValue]
        var text: [String]
        var testDescription: String { changes.keys.sorted().joined(separator: " + ") + (only.map { " (\($0))" } ?? "") }

        init(_ changes: [String: SettingValue], _ text: String...) {
            self.changes = changes
            self.text = text
        }

        init(_ only: NavigatorConfig.Kind, _ changes: [String: SettingValue], _ text: String) {
            self.only = only
            self.changes = changes
            self.text = [text]
        }
    }

    /// Settings Oryx's samples show (research 02 §4.7; the goldens check them against Oryx's output).
    static let oryxMappings: [Mapping] = [
        Mapping(["tappingTerm": .number(250)], "#undef TAPPING_TERM\n#define TAPPING_TERM 250"),
        Mapping(["flowTap": .number(120)], "#define FLOW_TAP_TERM 120"),
        Mapping(["chordalHold": .bool(true)], "#define CHORDAL_HOLD"),
        Mapping(["chordalHold": .bool(true), "chordalHoldExcludeThumbs": .bool(true)], "'*'"),
        Mapping(["permissiveHold": .bool(true)], "#define PERMISSIVE_HOLD"),
        Mapping(["oneShotTimeout": .number(2000)], "#undef ONESHOT_TIMEOUT\n#define ONESHOT_TIMEOUT 2000"),
        Mapping(["comboTerm": .number(40)], "#define COMBO_TERM 40"),
        Mapping(["rgbTimeout": .number(2)], "#define RGB_MATRIX_TIMEOUT 120000"),
        Mapping(["wakeupDelay": .number(100)], "#define USB_SUSPEND_WAKEUP_DELAY 100"),
        Mapping(["autoshift": .bool(true)], "AUTO_SHIFT_ENABLE = yes"),
        Mapping(["autoshift": .bool(true), "autoshiftTimeout": .number(150)], "#define AUTO_SHIFT_TIMEOUT 150"),
        Mapping(["mouseInterval": .number(14)], "#undef MOUSEKEY_INTERVAL\n#define MOUSEKEY_INTERVAL 14"),
        Mapping(["mouseDelay": .number(8)], "#undef MOUSEKEY_DELAY\n#define MOUSEKEY_DELAY 8"),
        Mapping(["capsLockStatus": .bool(true)], "#define CAPS_LOCK_STATUS"),
        // Without dynamic tapping term keys there is no `g_tapping_term` to offset: the key's case (an offset that
        // depends on the global term) and the default both use TAPPING_TERM.
        Mapping(["perKeyTappingTerm": .bool(true)], "#define TAPPING_TERM_PER_KEY", "return TAPPING_TERM ", "return TAPPING_TERM;"),
        Mapping(["disabledAnimations": .strings(["breathing"])], "#undef ENABLE_RGB_MATRIX_BREATHING"),
        Mapping(["enableDynamicMacros": .bool(true)], "DYNAMIC_MACRO_ENABLE = yes"),
        Mapping(["ambidexLT": .bool(true)]),
        Mapping(["dancesTapAction": .bool(false)]),
        Mapping(.trackpad, ["automouseTime": .number(500)], "#define AUTOMOUSE_TIMEOUT 500"),
        Mapping(.trackpad, ["automouseThreshold": .number(20)], "#define AUTOMOUSE_THRESHOLD 20"),
        Mapping(.trackball, ["automouseTime": .number(500)], "#define AUTO_MOUSE_TIME 500"),
        Mapping(.trackball, ["automouseThreshold": .number(20)], "#define AUTO_MOUSE_THRESHOLD 20"),
        Mapping(.trackball, ["sensitivity": .number(60)], "#define NAVIGATOR_TRACKBALL_CPI 60"),
        Mapping(.trackball, ["invertScrollX": .bool(true)], "#define NAVIGATOR_SCROLL_INVERT_X"),
        Mapping(.trackball, ["invertScrollY": .bool(true)], "#define NAVIGATOR_SCROLL_INVERT_Y"),
    ]

    /// Settings Oryx's samples never show, in Sextant's own mapping.
    static let ownMappings: [Mapping] = [
        Mapping(["debounce": .number(8)], "#undef DEBOUNCE\n#define DEBOUNCE 8"),
        Mapping(["tapCodeDelay": .bool(true)], "#define TAP_CODE_DELAY 10"),
        Mapping(["oneShotTapToggle": .number(3)], "#undef ONESHOT_TAP_TOGGLE\n#define ONESHOT_TAP_TOGGLE 3"),
        Mapping(["retroTapping": .bool(true)], "#define RETRO_TAPPING"),
        Mapping(["holdOnOtherKeyPress": .bool(true)], "#define HOLD_ON_OTHER_KEY_PRESS"),
        Mapping(["tappingForceHold": .bool(true)], "#define QUICK_TAP_TERM 0"),
        Mapping(["autoshiftModifiers": .bool(true)], "#define AUTO_SHIFT_MODIFIERS"),
        Mapping(["autoshiftEnableSpecial": .bool(false)], "#define NO_AUTO_SHIFT_SYMBOLS"),
        Mapping(["autoshiftEnableNumeric": .bool(false)], "#define NO_AUTO_SHIFT_NUMERIC"),
        Mapping(["autoshiftEnableAlpha": .bool(false)], "#define NO_AUTO_SHIFT_ALPHA"),
        Mapping(["autoshiftEnableTab": .bool(false)], "#define NO_AUTO_SHIFT_TAB"),
        Mapping(["mouseMaxSpeed": .number(12)], "#undef MOUSEKEY_MAX_SPEED\n#define MOUSEKEY_MAX_SPEED 12"),
        Mapping(["mouseTimeToMax": .number(60)], "#undef MOUSEKEY_TIME_TO_MAX\n#define MOUSEKEY_TIME_TO_MAX 60"),
        Mapping(["mouseWheelInterval": .number(100)], "#undef MOUSEKEY_WHEEL_INTERVAL\n#define MOUSEKEY_WHEEL_INTERVAL 100"),
        Mapping(["mouseWheelMaxSpeed": .number(4)], "#undef MOUSEKEY_WHEEL_MAX_SPEED\n#define MOUSEKEY_WHEEL_MAX_SPEED 4"),
        Mapping(["mouseWheelTimeToMaxSpeed": .number(20)], "#undef MOUSEKEY_WHEEL_TIME_TO_MAX\n#define MOUSEKEY_WHEEL_TIME_TO_MAX 20"),
        Mapping(["mouseWheelDelay": .number(200)], "#undef MOUSEKEY_WHEEL_DELAY\n#define MOUSEKEY_WHEEL_DELAY 200"),
        Mapping(["rgbHueStep": .number(12)], "#undef RGB_MATRIX_HUE_STEP\n#define RGB_MATRIX_HUE_STEP 12"),
        Mapping(["rgbBriStep": .number(8)], "#undef RGB_MATRIX_VAL_STEP\n#define RGB_MATRIX_VAL_STEP 8"),
        Mapping(["rgbUsbSuspend": .bool(false)], "#undef RGB_MATRIX_SLEEP"),
        Mapping(["layerLockIdleTimeout": .number(360)], "#undef LAYER_LOCK_IDLE_TIMEOUT\n#define LAYER_LOCK_IDLE_TIMEOUT 360000"),
        Mapping(["lowPollingRate": .bool(true)], "#define USB_POLLING_INTERVAL_MS 10"),
        Mapping(["disableNKRO": .bool(true)], "NKRO_ENABLE = no"),
        Mapping(["disableUsbStartupCheck": .bool(true)], "NO_USB_STARTUP_CHECK = yes"),
        Mapping(.trackpad, ["rotation": .number(-90)], "#define NAVIGATOR_TRACKPAD_ROTATION 270"),
        Mapping(.trackpad, ["oneShotAutoMouse": .bool(true)], "#define AUTOMOUSE_ONESHOT\n"),
        Mapping(
            .trackpad, ["oneShotAutoMouse": .bool(true), "oneShotAutoMouseTimeout": .number(15)],
            "#define AUTOMOUSE_ONESHOT_TIMEOUT 15000"),
        Mapping(.trackball, ["rotation": .number(-30)], "#define NAVIGATOR_TRACKBALL_ROTATION 330"),
        Mapping(.trackball, ["oneShotAutoMouse": .bool(true)], "#define AUTO_MOUSE_ONESHOT"),
        Mapping(.trackball, ["scrollOnly": .bool(true)], "#define NAVIGATOR_TRACKBALL_SCROLL_ONLY"),
        Mapping(.trackball, ["aimSpeed": .number(0)], "#define NAVIGATOR_AIM_DIVIDER 4"),
        Mapping(.trackball, ["turboSpeed": .number(2)], "#define NAVIGATOR_TURBO_MULTIPLIER 4"),
        Mapping(.trackball, ["aimLayers": .integers([1])], "#define NAVIGATOR_AIM_LAYERS { 1 }"),
        Mapping(.trackball, ["turboLayers": .integers([2])], "#define NAVIGATOR_TURBO_LAYERS { 2 }"),
        Mapping(.trackball, ["dragScrollLayers": .integers([1, 2])], "#define NAVIGATOR_DRAG_SCROLL_LAYERS { 1, 2 }"),
    ]

    /// Settings the generator refuses to change until they're decided (ADR 0040; Space Cadet and legacy dances: v1 2.3).
    /// Lifting one means dropping it here and adding its `Mapping`, which also puts it in the every-setting layout that
    /// RealToolchainTests compiles.
    static let stillRefused = ["liveTraining", "stenography", "geminipr", "legacyDualFunctionDances", "enableSpaceCadet"]

    /// The user's layout with `kind`, an automouse layer, a mouse key, a layer lock key and a per-key tapping term, so
    /// every setting reaches code the firmware compiles.
    static func settingsLayout(_ kind: NavigatorConfig.Kind) throws -> KeyboardLayout {
        var layout = try KeyboardLayout(
            oryxJSON: Data(contentsOf: QMKGeneratorGoldenTests.examples.appending(path: "my-layout-KlgM7-full.json")))
        layout.setNavigator(kind)
        layout.automouseLayer = 2
        layout.updateKey(layer: 1, index: 1) { $0 = Key("KC_MS_UP") }
        layout.updateKey(layer: 1, index: 2) { $0 = Key("QK_LLCK") }
        layout.updateKey(layer: 0, index: 51) { $0.tappingTerm = 240 }
        return layout
    }

    /// Stores values as an import would, defaults included; nil removes one.
    static func set(_ values: [String: SettingValue?], in layout: inout KeyboardLayout) throws {
        for (id, value) in values {
            let setting = try #require(SettingsCatalog.voyager.setting(id: id))
            if setting.navigatorKinds != nil { layout.navigator?.options[id] = value } else { layout.settings[id] = value }
        }
    }

    /// Every setting the generator writes, changed at once, with `kind` (RealToolchainTests compiles it).
    static func everySettingChanged(_ kind: NavigatorConfig.Kind) throws -> KeyboardLayout {
        var layout = try settingsLayout(kind)
        for mapping in oryxMappings + ownMappings where mapping.only ?? kind == kind { try set(mapping.changes, in: &layout) }
        return layout
    }

    func source(_ layout: KeyboardLayout) throws -> String {
        try QMKGenerator().generate(layout, identity: identity).files.sorted { $0.key < $1.key }.map(\.value).joined(separator: "\n")
    }

    @Test(arguments: oryxMappings + ownMappings)
    func writesEachChangedSetting(mapping: Mapping) throws {
        var layout = try Self.settingsLayout(mapping.only ?? .trackpad)
        let unchanged = try source(layout)
        try Self.set(mapping.changes, in: &layout)
        let changed = try source(layout)
        for text in mapping.text { #expect(changed.contains(text) && !unchanged.contains(text), "\(text)") }
    }

    /// Imported layouts may store a default; Sextant's own lines appear only away from it.
    @Test(arguments: ownMappings)
    func writesNothingAtTheDefault(mapping: Mapping) throws {
        var layout = try Self.settingsLayout(mapping.only ?? .trackpad)
        let unchanged = try source(layout)
        for id in mapping.changes.keys {
            try Self.set([id: try #require(SettingsCatalog.voyager.setting(id: id)).unsetValue], in: &layout)
        }
        #expect(try source(layout) == unchanged)
    }

    /// Every setting the Voyager shows is written, or refused by name, and all of them build together.
    @Test(arguments: [NavigatorConfig.Kind.trackpad, .trackball])
    func writesEverySettingAtOnce(kind: NavigatorConfig.Kind) throws {
        let shown = SettingsCatalog.voyager.sections.filter { $0.isVisibleOnVoyager && $0.id != "international" }
            .flatMap(\.settings).filter(\.appliesToVoyager).map(\.id)
        let mappings = Self.oryxMappings + Self.ownMappings
        #expect(Set(shown) == Set(mappings.flatMap(\.changes.keys) + Self.stillRefused))
        let changed = try source(Self.everySettingChanged(kind))
        for text in mappings.filter({ $0.only ?? kind == kind }).flatMap(\.text) { #expect(changed.contains(text), "\(text)") }
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
