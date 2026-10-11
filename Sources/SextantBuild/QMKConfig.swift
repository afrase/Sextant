import Foundation
import SextantApplication
import SextantDomain

/// The layout-wide switches: settings, features the keys need, and the Navigator. Renders `config.h`, `rules.mk` and
/// `keymap.json` in the order Oryx writes them.
struct Features {
    enum Pointing { case trackpad, trackball }

    let plan: KeymapPlan
    let pointing: Pointing?
    /// The Navigator's automouse layer, when it has one.
    let automouseLayer: Int?
    private var settings: [String: SettingValue] { plan.layout.settings }

    init(_ plan: KeymapPlan) throws(GeneratorError) {
        self.plan = plan
        try Self.refuseUnsupportedSettings(plan.layout.settings)
        if let navigator = plan.layout.navigator {
            pointing = try Self.pointing(navigator)
            let layer = plan.layout.automouseLayer
            if let layer, !plan.layout.layers.indices.contains(layer) {
                throw .unsupported(String(localized: "a Navigator automouse layer that doesn't exist"), nil)
            }
            automouseLayer = layer
        } else {
            pointing = nil
            automouseLayer = nil
        }
    }

    // MARK: Switches

    func flag(_ id: String) -> Bool { settings[id]?.boolValue == true }
    func number(_ id: String) -> Int? { settings[id]?.doubleValue.flatMap { Int(exactly: $0.rounded()) } }
    private func navigatorNumber(_ id: String) -> Int? {
        plan.layout.navigator?.options[id]?.doubleValue.flatMap { Int(exactly: $0.rounded()) }
    }
    private func uses(_ test: (String) -> Bool) -> Bool { plan.codes.contains(where: test) }

    var tappingTerm: Int { number("tappingTerm") ?? 200 }
    var perKeyTappingTerm: Bool { flag("perKeyTappingTerm") }
    var capsLockStatus: Bool { flag("capsLockStatus") }
    var chordalHold: Bool { flag("chordalHold") }
    var autoshift: Bool { flag("autoshift") }
    /// Mouse keys proper (the jiggler and double-click come from ZSA modules, not QMK's mouse keys).
    var usesMouseKeys: Bool {
        uses { KeycodeCatalog.entry(for: $0)?.category == .mouse && !["KC_MS_JIGGLER_TOGGLE", "KC_MS_DBL_CLICK"].contains($0) }
    }
    var usesConsumerKeys: Bool {
        uses { KeycodeCatalog.entry(for: $0)?.category == .media || $0.hasPrefix("KC_WWW_") || $0.hasPrefix("KC_BRIGHTNESS_") }
    }
    var usesJiggler: Bool { plan.codes.contains("KC_MS_JIGGLER_TOGGLE") }

    // MARK: config.h

    func configH(serial: String) -> String {
        var out: [String] = []
        func redefine(_ name: String, _ value: Int) { out += ["#undef \(name)", "#define \(name) \(value)", ""] }
        if let term = number("tappingTerm"), term != 200 { redefine("TAPPING_TERM", term) }
        if let flow = number("flowTap") { out.append("#define FLOW_TAP_TERM \(flow)") }
        if chordalHold { out.append("#define CHORDAL_HOLD") }
        if flag("permissiveHold") { out.append("#define PERMISSIVE_HOLD") }
        if let timeout = number("oneShotTimeout") { redefine("ONESHOT_TIMEOUT", timeout) }
        if let term = number("comboTerm") { out += ["#define COMBO_TERM \(term)", ""] }
        if let minutes = number("rgbTimeout"), minutes > 0 { redefine("RGB_MATRIX_TIMEOUT", minutes * 60000) }
        out.append("#define USB_SUSPEND_WAKEUP_DELAY \(number("wakeupDelay") ?? 0)")
        if autoshift, let timeout = number("autoshiftTimeout") { out.append("#define AUTO_SHIFT_TIMEOUT \(timeout)") }
        if let interval = number("mouseInterval") { redefine("MOUSEKEY_INTERVAL", interval) }
        if let delay = number("mouseDelay") { redefine("MOUSEKEY_DELAY", delay) }
        if capsLockStatus { out.append("#define CAPS_LOCK_STATUS") }
        out.append("#define SERIAL_NUMBER \"\(serial)\"")  // the generator admits only [A-Za-z0-9/._-]
        let layers = plan.layout.layers.count
        out.append("#define LAYER_STATE_\(layers < 8 ? 8 : layers < 16 ? 16 : 32)BIT")
        if !plan.combos.isEmpty { out += ["#define COMBO_COUNT \(plan.combos.count)", ""] }
        out += navigatorDefines()
        if perKeyTappingTerm { out.append("#define TAPPING_TERM_PER_KEY") }
        out += ["#define RGB_MATRIX_STARTUP_SPD 60", ""]
        if case let .strings(disabled)? = settings["disabledAnimations"] {
            out += QMKCodes.animations.filter { disabled.contains($0.id) }.map { "#undef ENABLE_RGB_MATRIX_\($0.effect)" }
        }
        return out.joined(separator: "\n") + "\n"
    }

    private func navigatorDefines() -> [String] {
        let time = navigatorNumber("automouseTime") ?? 650
        let threshold = navigatorNumber("automouseThreshold") ?? 10
        switch pointing {
        case .trackpad?:
            guard let layer = automouseLayer else { return [] }
            return ["#define AUTOMOUSE_LAYER \(layer)", "#define AUTOMOUSE_TIMEOUT \(time)", "#define AUTOMOUSE_THRESHOLD \(threshold)"]
        case .trackball?:
            var out = [
                "#define WHEEL_EXTENDED_SUPPORT", "#define POINTING_DEVICE_HIRES_SCROLL_ENABLE",
                "#define POINTING_DEVICE_HIRES_SCROLL_EXPONENT 1", "#define POINTING_DEVICE_GESTURES_CURSOR_GLIDE_ENABLE",
                "#define MOUSE_EXTENDED_REPORT",
            ]
            if let cpi = navigatorNumber("sensitivity") { out.append("#define NAVIGATOR_TRACKBALL_CPI \(cpi)") }
            out += ["#define NAVIGATOR_SCROLL_DIVIDER 75", ""]
            if let layer = automouseLayer {
                out += [
                    "#define POINTING_DEVICE_AUTO_MOUSE_ENABLE", "#define AUTO_MOUSE_DEFAULT_LAYER \(layer)",
                    "#define AUTO_MOUSE_TIME \(time)", "#define AUTO_MOUSE_THRESHOLD \(threshold)",
                    "#define AUTO_MOUSE_SCROLL_THRESHOLD AUTO_MOUSE_THRESHOLD / NAVIGATOR_SCROLL_DIVIDER",
                ]
            }
            for axis in ["X", "Y"] where plan.layout.navigator?.options["invertScroll\(axis)"] == .bool(true) {
                out.append("#define NAVIGATOR_SCROLL_INVERT_\(axis)")
            }
            return out
        case nil: return []
        }
    }

    // MARK: rules.mk and keymap.json

    func rulesMk() -> String {
        var out = ["CONSOLE_ENABLE = no", "COMMAND_ENABLE = no"]
        if !usesMouseKeys { out.append("MOUSEKEY_ENABLE = no") }
        if autoshift { out.append("AUTO_SHIFT_ENABLE = yes") }
        out += ["ORYX_ENABLE = yes", "RGB_MATRIX_CUSTOM_KB = yes"]
        if flag("enableDynamicMacros") || uses({ $0.hasPrefix("DM_") }) { out.append("DYNAMIC_MACRO_ENABLE = yes") }
        if !plan.dances.isEmpty { out.append("TAP_DANCE_ENABLE = yes") }
        out.append("SPACE_CADET_ENABLE = no")
        if plan.codes.contains("CW_TOGG") { out.append("CAPS_WORD_ENABLE = yes") }
        if plan.codes.contains("QK_REP") || plan.codes.contains("QK_AREP") { out.append("REPEAT_KEY_ENABLE = yes") }
        if !plan.combos.isEmpty { out.append("COMBO_ENABLE = yes") }
        if uses({ ["DT_UP", "DT_DOWN", "DT_PRNT"].contains($0) }) { out.append("DYNAMIC_TAPPING_TERM_ENABLE = yes") }
        if plan.codes.contains("QK_LLCK") { out.append("LAYER_LOCK_ENABLE = yes") }
        switch pointing {
        case .trackpad?:
            out += ["PRECISION_TRACKPAD_ENABLE = yes", "PRECISION_TRACKPAD_DRIVER = navigator_trackpad"]
            if automouseLayer != nil { out.append("POINTING_DEVICE_DRIVER = custom") }
        // The `zsa/navigator_trackball` module sets its own driver; the pinned firmware refuses `navigator_trackball` here.
        case .trackball?: out.append("POINTING_DEVICE_ENABLE = yes")
        case nil: break
        }
        return out.joined(separator: "\n") + "\n"
    }

    /// QMK community modules. `zsa/oryx` keeps the live protocol (Keymapp, Oryx, Sextant) and `zsa/defaults` ZSA's
    /// keycodes; the trackpad module keeps the Navigator trackpad working, the trackball module drives the trackball.
    func keymapJSON() -> String {
        var modules = ["zsa/oryx"]
        if usesJiggler { modules.append("zsa/mousejiggler") }
        if plan.codes.contains("KC_MS_DBL_CLICK") { modules.append("zsa/doubleclick") }
        switch pointing {
        case .trackpad?:
            modules.append("zsa/navigator_trackpad")
            if automouseLayer != nil { modules.append("zsa/automouse") }
        case .trackball?: modules.append("zsa/navigator_trackball")
        case nil: break
        }
        modules.append("zsa/defaults")
        let list = modules.map { "        \"\($0)\"" }.joined(separator: ",\n")
        return "{\n    \"modules\": [\n\(list)\n    ]\n}\n"
    }

    // MARK: Refusals

    /// Settings this generator writes, or that don't change the firmware.
    private static let understood: Set<String> = [
        "tappingTerm", "flowTap", "chordalHold", "chordalHoldExcludeThumbs", "permissiveHold", "oneShotTimeout", "comboTerm",
        "rgbTimeout", "wakeupDelay", "autoshift", "autoshiftTimeout", "mouseInterval", "mouseDelay", "capsLockStatus",
        "perKeyTappingTerm", "disabledAnimations", "enableDynamicMacros", "enableNavigator", "ambidexLT",
        // Same tap-dance code either way in Oryx's output (JRGQm has it off).
        "dancesTapAction",
    ]

    /// A changed firmware setting the generator can't write fails the build rather than being dropped, and so does a
    /// number outside the setting's range (imported values feed C defines and arithmetic). Locale toggles only change
    /// Oryx's picker; the codes a layout uses carry the locale.
    private static func refuseUnsupportedSettings(_ settings: [String: SettingValue]) throws(GeneratorError) {
        let catalog = SettingsCatalog.voyager
        for (id, value) in settings.sorted(by: { $0.key < $1.key }) {
            guard let setting = catalog.setting(id: id) else { continue }
            let outOfRange = value.doubleValue.map { v in setting.range.map { !$0.contains(v) } ?? false } ?? false
            let unwritten =
                !understood.contains(id) && value != setting.defaultValue && catalog.section(containing: id)?.id != "international"
            if outOfRange || unwritten { throw .unsupported(String(localized: "the “\(setting.title)” setting"), nil) }
        }
    }

    /// Navigator options with no firmware output at these values (Oryx's defaults, as its sources show), besides the
    /// catalog defaults.
    private static let quietOptions: [String: SettingValue] = [
        "tap": .bool(true), "tapRight": .bool(true), "scrollInertia": .bool(true), "scrollWithTwoFingers": .bool(true),
        "scrollSensitivity": .number(2),
    ]

    private static func pointing(_ navigator: NavigatorConfig) throws(GeneratorError) -> Pointing {
        let kind: Pointing
        var written: Set<String> = ["automouseTime", "automouseThreshold"]
        switch navigator.kind {
        case .trackpad: kind = .trackpad
        case .trackball:
            kind = .trackball
            written.formUnion(["sensitivity", "invertScrollX", "invertScrollY"])
        case .knob: throw .unsupported(String(localized: "the Navigator knob"), nil)
        }
        // Written numbers feed C defines, so they must be in the option's range, like settings.
        for (id, value) in navigator.options.sorted(by: { $0.key < $1.key }) {
            let setting = SettingsCatalog.voyager.setting(id: id)
            let outOfRange = value.doubleValue.map { v in setting?.range.map { !$0.contains(v) } ?? false } ?? false
            let unwritten = !written.contains(id) && quietOptions[id] != value && setting?.defaultValue != value
            if outOfRange || unwritten { throw .unsupported(String(localized: "the Navigator's “\(id)” option"), nil) }
        }
        return kind
    }
}
