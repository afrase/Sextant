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
            pointing = try Self.pointing(navigator, layers: plan.layout.layers.count)
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
    /// A stored value other than the default (any stored value, for a slider that is off by default).
    private func changed(_ id: String) -> Bool { settings[id].map { $0 != SettingsCatalog.voyager.setting(id: id)?.defaultValue } ?? false }
    private func navigatorNumber(_ id: String) -> Int? {
        plan.layout.navigator?.options[id]?.doubleValue.flatMap { Int(exactly: $0.rounded()) }
    }
    private func navigatorFlag(_ id: String) -> Bool { plan.layout.navigator?.options[id] == .bool(true) }
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
    var usesDynamicTappingTerm: Bool { uses { ["DT_UP", "DT_DOWN", "DT_PRNT"].contains($0) } }

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
        out += ownDefines()
        return out.joined(separator: "\n") + "\n"
    }

    /// Sextant's own lines (ADR 0040), after Oryx's.
    private func ownDefines() -> [String] {
        let numbers = Self.ownNumbers.filter { changed($0.id) }.flatMap { id, name, scale in
            number(id).map { ["#undef \(name)", "#define \(name) \($0 * scale)", ""] } ?? []
        }
        return numbers + Self.ownToggles.filter { changed($0.id) }.flatMap(\.lines)
    }

    private func navigatorDefines() -> [String] {
        let time = navigatorNumber("automouseTime") ?? 650
        let threshold = navigatorNumber("automouseThreshold") ?? 10
        // Clockwise in both modules. C's % keeps the sign, so 0–359 keeps the trackball's right-angle paths for -90 and -180.
        let rotation = navigatorNumber("rotation").map { ($0 % 360 + 360) % 360 }.flatMap { $0 == 0 ? nil : $0 }
        switch pointing {
        case .trackpad?:
            var out = rotation.map { ["#define NAVIGATOR_TRACKPAD_ROTATION \($0)"] } ?? []
            guard let layer = automouseLayer else { return out }
            out += ["#define AUTOMOUSE_LAYER \(layer)", "#define AUTOMOUSE_TIMEOUT \(time)", "#define AUTOMOUSE_THRESHOLD \(threshold)"]
            if navigatorFlag("oneShotAutoMouse") {
                out.append("#define AUTOMOUSE_ONESHOT")
                if let seconds = navigatorNumber("oneShotAutoMouseTimeout") {
                    out.append("#define AUTOMOUSE_ONESHOT_TIMEOUT \(seconds * 1000)")
                }
            }
            return out
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
            for axis in ["X", "Y"] where navigatorFlag("invertScroll\(axis)") {
                out.append("#define NAVIGATOR_SCROLL_INVERT_\(axis)")
            }
            if let rotation { out.append("#define NAVIGATOR_TRACKBALL_ROTATION \(rotation)") }
            if navigatorFlag("scrollOnly") { out.append("#define NAVIGATOR_TRACKBALL_SCROLL_ONLY") }
            // Slow, normal and fast: the module's 3 is normal.
            if let aim = navigatorNumber("aimSpeed"), aim != 1 { out.append("#define NAVIGATOR_AIM_DIVIDER \(4 - aim)") }
            if let turbo = navigatorNumber("turboSpeed"), turbo != 1 { out.append("#define NAVIGATOR_TURBO_MULTIPLIER \(2 + turbo)") }
            for (id, mode) in [("aimLayers", "AIM"), ("turboLayers", "TURBO"), ("dragScrollLayers", "DRAG_SCROLL")] {
                if case let .integers(layers)? = plan.layout.navigator?.options[id], !layers.isEmpty {
                    out.append("#define NAVIGATOR_\(mode)_LAYERS { \(layers.map(String.init).joined(separator: ", ")) }")
                }
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
        if usesDynamicTappingTerm { out.append("DYNAMIC_TAPPING_TERM_ENABLE = yes") }
        if plan.codes.contains("QK_LLCK") { out.append("LAYER_LOCK_ENABLE = yes") }
        switch pointing {
        case .trackpad?:
            out += ["PRECISION_TRACKPAD_ENABLE = yes", "PRECISION_TRACKPAD_DRIVER = navigator_trackpad"]
            if automouseLayer != nil { out.append("POINTING_DEVICE_DRIVER = custom") }
        // The `zsa/navigator_trackball` module sets its own driver; the pinned firmware refuses `navigator_trackball` here.
        case .trackball?: out.append("POINTING_DEVICE_ENABLE = yes")
        case nil: break
        }
        // Sextant's own mapping (ADR 0040). keyboard.json turns NKRO on; the keymap's rules.mk is read after it.
        if flag("disableNKRO") { out.append("NKRO_ENABLE = no") }
        if flag("disableUsbStartupCheck") { out.append("NO_USB_STARTUP_CHECK = yes") }
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

    // MARK: Sextant's own mapping

    /// Numbers Oryx's samples never showed (ADR 0040): the define each sets away from its default, in units of `scale`.
    /// Each is #undef'd first: the board's config.h or QMK's info_config.h defines some of them.
    private static let ownNumbers: [(id: String, define: String, scale: Int)] = [
        ("debounce", "DEBOUNCE", 1), ("oneShotTapToggle", "ONESHOT_TAP_TOGGLE", 1),
        ("mouseMaxSpeed", "MOUSEKEY_MAX_SPEED", 1), ("mouseTimeToMax", "MOUSEKEY_TIME_TO_MAX", 1),
        ("mouseWheelInterval", "MOUSEKEY_WHEEL_INTERVAL", 1), ("mouseWheelMaxSpeed", "MOUSEKEY_WHEEL_MAX_SPEED", 1),
        ("mouseWheelTimeToMaxSpeed", "MOUSEKEY_WHEEL_TIME_TO_MAX", 1), ("mouseWheelDelay", "MOUSEKEY_WHEEL_DELAY", 1),
        ("rgbHueStep", "RGB_MATRIX_HUE_STEP", 1), ("rgbBriStep", "RGB_MATRIX_VAL_STEP", 1),
        ("layerLockIdleTimeout", "LAYER_LOCK_IDLE_TIMEOUT", 1000),
    ]

    /// Toggles Oryx's samples never showed (ADR 0040): the lines each writes away from its default.
    private static let ownToggles: [(id: String, lines: [String])] = [
        ("tapCodeDelay", ["#define TAP_CODE_DELAY 10"]),
        ("retroTapping", ["#define RETRO_TAPPING"]),
        ("holdOnOtherKeyPress", ["#define HOLD_ON_OTHER_KEY_PRESS"]),
        // The pinned firmware has no TAPPING_FORCE_HOLD; a zero quick-tap term replaced it.
        ("tappingForceHold", ["#define QUICK_TAP_TERM 0"]),
        ("autoshiftModifiers", ["#define AUTO_SHIFT_MODIFIERS"]),
        // NO_AUTO_SHIFT_SPECIAL would drop Tab too, which has its own toggle.
        ("autoshiftEnableSpecial", ["#define NO_AUTO_SHIFT_SYMBOLS"]),
        ("autoshiftEnableNumeric", ["#define NO_AUTO_SHIFT_NUMERIC"]),
        ("autoshiftEnableAlpha", ["#define NO_AUTO_SHIFT_ALPHA"]),
        ("autoshiftEnableTab", ["#define NO_AUTO_SHIFT_TAB"]),
        // keyboard.json turns RGB_MATRIX_SLEEP on.
        ("rgbUsbSuspend", ["#undef RGB_MATRIX_SLEEP"]),
        // The fastest interval USB allows a low-speed device, so hosts that expect only those keep up.
        ("lowPollingRate", ["#define USB_POLLING_INTERVAL_MS 10"]),
    ]

    // MARK: Refusals

    /// Settings this generator writes, or that don't change the firmware.
    private static let understood = Set([
        "tappingTerm", "flowTap", "chordalHold", "chordalHoldExcludeThumbs", "permissiveHold", "oneShotTimeout", "comboTerm",
        "rgbTimeout", "wakeupDelay", "autoshift", "autoshiftTimeout", "mouseInterval", "mouseDelay", "capsLockStatus",
        "perKeyTappingTerm", "disabledAnimations", "enableDynamicMacros", "enableNavigator", "ambidexLT",
        // Same tap-dance code either way in Oryx's output (JRGQm has it off).
        "dancesTapAction",
        "disableNKRO", "disableUsbStartupCheck",
    ]).union(ownNumbers.map(\.id)).union(ownToggles.map(\.id))

    /// A changed firmware setting the generator can't write fails the build rather than being dropped, and so does a
    /// number outside the setting's range or a value of the wrong type (imported values feed C defines and arithmetic).
    /// Locale toggles only change Oryx's picker; the codes a layout uses carry the locale.
    private static func refuseUnsupportedSettings(_ settings: [String: SettingValue]) throws(GeneratorError) {
        let catalog = SettingsCatalog.voyager
        for (id, value) in settings.sorted(by: { $0.key < $1.key }) {
            guard let setting = catalog.setting(id: id) else { continue }
            let outOfRange = value.doubleValue.map { v in setting.range.map { !$0.contains(v) } ?? false } ?? false
            let unwritten =
                !understood.contains(id) && value != setting.defaultValue && catalog.section(containing: id)?.id != "international"
            if outOfRange || unwritten || !fits(value, setting) {
                throw .unsupported(String(localized: "the “\(setting.title)” setting"), nil)
            }
        }
    }

    /// A toggle holds a Bool, a slider a number, and a picker its list (an empty list is either type).
    private static func fits(_ value: SettingValue, _ setting: Setting) -> Bool {
        switch (setting.control, value) {
        case (.toggle, .bool), (.slider, .number), (.layerSelect, .integers), (.animationSelect, .strings): true
        case (.layerSelect, _), (.animationSelect, _): value == .integers([])
        default: false
        }
    }

    /// Navigator options with no firmware output at these values (Oryx's defaults, as its sources show), besides the
    /// catalog defaults.
    private static let quietOptions: [String: SettingValue] = [
        "tap": .bool(true), "tapRight": .bool(true), "scrollInertia": .bool(true), "scrollWithTwoFingers": .bool(true),
        "scrollSensitivity": .number(2),
    ]

    private static func pointing(_ navigator: NavigatorConfig, layers: Int) throws(GeneratorError) -> Pointing {
        let kind: Pointing
        var written: Set<String> = ["automouseTime", "automouseThreshold", "rotation", "oneShotAutoMouseTimeout"]
        switch navigator.kind {
        case .trackpad:
            kind = .trackpad
            written.insert("oneShotAutoMouse")
        case .trackball:
            // Not one-shot auto-mouse: the trackball runs QMK's own auto mouse, which has no one-shot mode.
            kind = .trackball
            written.formUnion([
                "sensitivity", "invertScrollX", "invertScrollY", "scrollOnly", "aimSpeed", "turboSpeed", "aimLayers", "turboLayers",
                "dragScrollLayers",
            ])
        case .knob: throw .unsupported(String(localized: "the Navigator knob"), nil)
        }
        // Written values feed C defines, so they must fit the option, like settings, and name layers that exist.
        for (id, value) in navigator.options.sorted(by: { $0.key < $1.key }) {
            let setting = SettingsCatalog.voyager.setting(id: id)
            let outOfRange = value.doubleValue.map { v in setting?.range.map { !$0.contains(v) } ?? false } ?? false
            let unwritten = !written.contains(id) && quietOptions[id] != value && setting?.defaultValue != value
            let misfit = setting.map { !fits(value, $0) } ?? false
            let missingLayer = if case let .integers(list) = value { list.contains { !(0..<layers).contains($0) } } else { false }
            if outOfRange || unwritten || misfit || missingLayer {
                throw .unsupported(String(localized: "the Navigator's “\(id)” option"), nil)
            }
        }
        return kind
    }
}
