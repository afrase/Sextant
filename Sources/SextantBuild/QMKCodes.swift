import Foundation
import SextantDomain

/// How actions become QMK C expressions and statements, plus the QMK data tables the generator needs.
enum QMKCodes {
    /// A QMK colour: hue, saturation and value, 0...255 each.
    struct HSV: Hashable {
        var h: Int
        var s: Int
        var v: Int

        // Oryx keeps a finer HSV than its hex, so its hue can differ by up to 2 steps (research 02 §4.6).
        init(_ color: HexColor) {
            let c = color.hsb
            h = Int((c.hue * 256).rounded()) % 256
            s = Int((c.saturation * 255).rounded())
            v = Int((c.brightness * 255).rounded())
        }

        var triple: String { "{\(h),\(s),\(v)}" }
    }

    /// The keycode as `keymap.c` writes it: as stored, as Oryx writes it, unless the pinned QMK has dropped that legacy
    /// spelling (``undeclaredLegacyNames``), when it is the catalog's own code, which QMK declares. A stored `KC_BSPACE`
    /// becomes `KC_BSPC`; `KC_NUBS`, which QMK still declares, stays.
    static func name(_ code: String) -> String {
        undeclaredLegacyNames.contains(code) ? KeycodeCatalog.canonicalCode(code) : code
    }

    /// The catalog's other spellings of a code (``KeycodeEntry/aliases``) that the pinned QMK (`ToolchainPins.firmwareCommit`)
    /// doesn't declare in the headers a keymap sees: `keycodes.h`, `quantum_keycodes.h`, `keymap_us.h`,
    /// `quantum_keycodes_legacy.h` and the `zsa/*` modules' keycodes. Written as stored, each fails the build.
    /// `MOON_LED_LEVEL` isn't here: `keymap.c` defines it. `QMKKeycodeNameTests` checks this list against the headers
    /// when the toolchain is set up.
    static let undeclaredLegacyNames: Set<String> = [
        "KC_LCTRL", "KC_LSHIFT", "KC_RCTRL", "KC_RSHIFT", "KC_CAPSLOCK", "KC_CLCK", "CAPS_WORD",
        "KC_LSPO", "KC_RSPC", "KC_LCPO", "KC_RCPC", "KC_LAPO", "KC_RAPC", "KC_SFTENT",
        "KC_LBRACKET", "KC_RBRACKET", "KC_BSLASH", "KC_SCOLON", "KC_ZKHK", "KC_PERIOD", "KC_NONUS_BSLASH",
        "KC_PGDOWN", "KC_BSPACE", "KC__VOLUP", "KC__VOLDOWN", "KC__MUTE",
        "RESET", "EEP_RST", "EEPROM_RESET", "MAGIC_TOGGLE_NKRO", "DEBUG",
        "KC_ASTG", "KC_ASON", "KC_ASOFF", "KC_ASUP", "KC_ASDN", "KC_ASRP", "CMB_TOG", "CMB_ON", "CMB_OFF",
        "DYN_REC_START1", "DYN_REC_START2", "DYN_MACRO_PLAY1", "DYN_MACRO_PLAY2", "DYN_REC_STOP",
        "KC_PSCREEN", "KC_SLCK", "KC_SCROLLLOCK", "KC_RO", "KC_KANA", "KC_JYEN", "KC_HENK", "KC_MHEN",
        "KC_LANG1", "KC_LANG2", "KC_LANG3", "KC_LANG4", "KC_LANG5", "KC_LANG6", "KC_LANG7", "KC_LANG8", "KC_LANG9",
        "KC_NUMLOCK", "KC_NLCK",
    ]

    /// Wraps a keycode in modifier functions in Oryx's nesting order, e.g. `LGUI(LSFT(KC_LBRC))`.
    static func wrap(_ code: String, _ modifiers: Modifiers) -> String {
        nest(code, modifiers, order: keycodeNesting, prefix: "")
    }

    /// A macro step: `SS_LCTL(SS_LSFT(SS_TAP(X_O)))`.
    static func macroStep(_ step: MacroStep) -> String {
        nest("SS_TAP(X_\(step.code.replacing(/^KC_/, with: "")))", step.modifiers, order: macroNesting, prefix: "SS_")
    }

    /// QMK `MOD_*` mask: `MOD_LSFT`, `MOD_HYPR`, or `MOD_LCTL | MOD_LSFT`.
    static func mask(_ modifiers: Modifiers) -> String { modifiers.qmkMaskNames.joined(separator: " | ") }

    /// `MT(MOD_LALT, KC_Z)`, `LT(1, KC_ENTER)` or `MEH_T(KC_ENTER)` when QMK can express the pair in one keycode:
    /// a plain basic tap and a single-modifier, `*_T` or momentary-layer (0–15) hold. Nil means a dual-function key.
    static func modTapOrLayerTap(tap: KeyAction, hold: KeyAction) -> String? {
        // The domain's rule, which combo triggers share (ADR 0046).
        guard Key.isModTapOrLayerTap(tap: tap, hold: hold) else { return nil }
        let tapName = name(tap.code)
        if hold.code.hasSuffix("_T") { return "\(hold.code)(\(tapName))" }
        if let m = KeycodeCatalog.modifier(forCode: hold.code), m.rawValue.nonzeroBitCount == 1 { return "MT(\(mask(m)), \(tapName))" }
        if hold.canonicalCode == "MO", let layer = hold.layer, (0...15).contains(layer) { return "LT(\(layer), \(tapName))" }
        return nil
    }

    /// C statements for an action inside a dual-function key or tap dance: on press, and on release (nil: nothing).
    /// Nil when the action can't run from user code (a macro, a colour key, a firmware keycode).
    static func statements(_ action: KeyAction) -> (press: String, release: String?)? {
        if action.macro == nil, let mods = heldModifiers(action) {
            return ("register_mods(\(modBits(mods)));", "unregister_mods(\(modBits(mods)));")
        }
        return switch action.canonicalCode {
        case _ where action.macro != nil: nil
        case "MO": action.layer.map { ("layer_on(\($0));", "if (!is_layer_locked(\($0))) { layer_off(\($0)); }") }
        case "TO": action.layer.map { ("layer_move(\($0));", nil) }
        case _ where isKeycode(action): send(wrap(name(action.code), action.modifiers))
        default: nil
        }
    }

    private static func send(_ code: String) -> (press: String, release: String?) {
        ("register_code16(\(code));", "unregister_code16(\(code));")
    }

    /// Modifiers alone: Oryx's Hyper and Meh holds (`ALL_T()` and `MEH_T()` need a tap) or a chorded modifier keycode.
    /// `register_code16` would press all but a modifier keycode as weak modifiers, which QMK drops at the next key press,
    /// so they go down as real ones. A bare modifier keycode stays on `register_code16`, as in Oryx's source.
    private static func heldModifiers(_ action: KeyAction) -> Modifiers? {
        guard let own = KeycodeCatalog.modifier(forCode: action.code) else { return nil }
        let all = own.union(action.modifiers)
        return all == own && own.rawValue.nonzeroBitCount == 1 ? nil : all
    }

    /// `MOD_BIT(KC_LEFT_CTRL) | MOD_BIT(KC_LEFT_SHIFT)`: the HID modifier byte, side exact. `Modifiers` uses the HID bit
    /// order; QMK's `MOD_*` masks are the 5-bit encoding, which can't mix sides.
    static func modBits(_ modifiers: Modifiers) -> String {
        let keycodes = [
            "KC_LEFT_CTRL", "KC_LEFT_SHIFT", "KC_LEFT_ALT", "KC_LEFT_GUI",
            "KC_RIGHT_CTRL", "KC_RIGHT_SHIFT", "KC_RIGHT_ALT", "KC_RIGHT_GUI",
        ]
        let held = keycodes.indices.filter { modifiers.rawValue & (1 << $0) != 0 }
        return held.map { "MOD_BIT(\(keycodes[$0]))" }.joined(separator: " | ")
    }

    /// True for codes `register_code16` can send: HID keycodes (``KeyAction/isHIDCode``) and the locale codes `i18n.h`
    /// defines.
    static func isKeycode(_ action: KeyAction) -> Bool {
        action.macro == nil && (action.isHIDCode || locale[action.code] != nil)
    }

    private static let keycodeNesting: [(Modifiers, String)] = [
        (.leftOption, "LALT"), (.leftCommand, "LGUI"), (.leftControl, "LCTL"), (.rightOption, "RALT"), (.rightCommand, "RGUI"),
        (.leftShift, "LSFT"), (.rightControl, "RCTL"), (.rightShift, "RSFT"),
    ]
    private static let macroNesting: [(Modifiers, String)] = [
        (.leftControl, "LCTL"), (.leftShift, "LSFT"), (.leftOption, "LALT"), (.leftCommand, "LGUI"), (.rightControl, "RCTL"),
        (.rightShift, "RSFT"), (.rightOption, "RALT"), (.rightCommand, "RGUI"),
    ]

    private static func nest(_ inner: String, _ modifiers: Modifiers, order: [(Modifiers, String)], prefix: String) -> String {
        order.reversed().reduce(inner) { s, pair in modifiers.contains(pair.0) ? "\(prefix)\(pair.1)(\(s))" : s }
    }

    /// Definitions for the locale codes Sextant's catalog offers (QMK `keymap_uk.h`, `keymap_us_international.h`) and
    /// Oryx's OS shortcut codes. `i18n.h` defines the ones a layout uses, as Oryx's does.
    static let locale: [String: String] = [
        "UK_GRV": "KC_GRV", "UK_MINS": "KC_MINS", "UK_HASH": "KC_NUHS", "UK_PERC": "S(KC_5)", "UK_DLR": "S(KC_4)",
        "UK_PND": "S(KC_3)", "UK_AT": "S(KC_QUOT)", "UK_TILD": "S(KC_NUHS)", "UK_PIPE": "S(KC_NUBS)", "UK_DQUO": "S(KC_2)",
        "UK_NOT": "S(KC_GRV)", "UK_EURO": "ALGR(KC_4)",
        "US_AACU": "ALGR(KC_A)", "US_EACU": "ALGR(KC_E)", "US_IACU": "ALGR(KC_I)", "US_OACU": "ALGR(KC_O)", "US_UACU": "ALGR(KC_U)",
        "US_UDIA": "ALGR(KC_Y)", "US_NTIL": "ALGR(KC_N)", "US_CCED": "ALGR(KC_COMM)", "US_EURO": "ALGR(KC_5)",
        "KC_MAC_COPY": "LGUI(KC_C)", "KC_MAC_CUT": "LGUI(KC_X)", "KC_MAC_PASTE": "LGUI(KC_V)", "KC_MAC_UNDO": "LGUI(KC_Z)",
        "KC_PC_COPY": "LCTL(KC_C)", "KC_PC_CUT": "LCTL(KC_X)", "KC_PC_PASTE": "LCTL(KC_V)", "KC_PC_UNDO": "LCTL(KC_Z)",
    ]

    /// Oryx animation ids → QMK RGB matrix effects, in QMK's effect order (the order `config.h` disables them in).
    static let animations: [(id: String, effect: String)] = [
        ("alphaMods", "ALPHAS_MODS"), ("gradientUpDown", "GRADIENT_UP_DOWN"), ("gradientLeftRight", "GRADIENT_LEFT_RIGHT"),
        ("breathing", "BREATHING"), ("bandSat", "BAND_SAT"), ("bandHue", "BAND_VAL"), ("spinBandSat", "BAND_PINWHEEL_SAT"),
        ("spinBandHue", "BAND_PINWHEEL_VAL"), ("spiralSat", "BAND_SPIRAL_SAT"), ("spiralVal", "BAND_SPIRAL_VAL"),
        ("cycleAll", "CYCLE_ALL"), ("cycleLeftRight", "CYCLE_LEFT_RIGHT"), ("cycleUpDown", "CYCLE_UP_DOWN"),
        ("cycleOutIn", "CYCLE_OUT_IN"), ("cycleOutInDual", "CYCLE_OUT_IN_DUAL"), ("rainbowChevron", "RAINBOW_MOVING_CHEVRON"),
        ("cyclePinwheel", "CYCLE_PINWHEEL"), ("cycleSpiral", "CYCLE_SPIRAL"), ("dualBeacon", "DUAL_BEACON"),
        ("rainbowBeacon", "RAINBOW_BEACON"), ("rainbowPinwheels", "RAINBOW_PINWHEELS"), ("flowerBlooming", "FLOWER_BLOOMING"),
        ("raindrops", "RAINDROPS"), ("jellybeansRaindrops", "JELLYBEAN_RAINDROPS"), ("hueBreathing", "HUE_BREATHING"),
        ("pendulum", "HUE_PENDULUM"), ("wave", "HUE_WAVE"), ("pixelFractal", "PIXEL_FRACTAL"), ("pixelFlow", "PIXEL_FLOW"),
        ("pixelRain", "PIXEL_RAIN"), ("typingHeatmap", "TYPING_HEATMAP"), ("digitalRain", "DIGITAL_RAIN"),
        ("reactiveSimple", "SOLID_REACTIVE_SIMPLE"), ("reactive", "SOLID_REACTIVE"), ("reactiveWide", "SOLID_REACTIVE_WIDE"),
        ("reactiveMultiwide", "SOLID_REACTIVE_MULTIWIDE"), ("reactiveCross", "SOLID_REACTIVE_CROSS"),
        ("reactiveMulticross", "SOLID_REACTIVE_MULTICROSS"), ("reactiveNexus", "SOLID_REACTIVE_NEXUS"),
        ("reactiveMultinexus", "SOLID_REACTIVE_MULTINEXUS"), ("reactiveSplash", "SPLASH"), ("reactiveMultisplash", "MULTISPLASH"),
        ("reactiveSolidSplash", "SOLID_SPLASH"), ("reactiveSolidMultisplash", "SOLID_MULTISPLASH"), ("starlight", "STARLIGHT"),
        ("starlightDualHue", "STARLIGHT_DUAL_HUE"), ("starlightDualSat", "STARLIGHT_DUAL_SAT"), ("riverflow", "RIVERFLOW"),
    ]
}
