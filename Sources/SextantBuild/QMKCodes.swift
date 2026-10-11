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
        guard tap.modifiers.isEmpty, tap.macro == nil, isBasic(tap.code), hold.macro == nil, hold.modifiers.isEmpty else { return nil }
        if hold.code.hasSuffix("_T") { return "\(hold.code)(\(tap.code))" }
        if let m = KeycodeCatalog.modifier(forCode: hold.code), m.rawValue.nonzeroBitCount == 1 { return "MT(\(mask(m)), \(tap.code))" }
        if hold.canonicalCode == "MO", let layer = hold.layer, (0...15).contains(layer) { return "LT(\(layer), \(tap.code))" }
        return nil
    }

    /// C statements for an action inside a dual-function key or tap dance: on press, and on release (nil: nothing).
    /// Nil when the action can't run from user code (a macro, a colour key, a firmware keycode).
    static func statements(_ action: KeyAction) -> (press: String, release: String?)? {
        switch action.canonicalCode {
        case _ where action.macro != nil: nil
        case "MO": action.layer.map { ("layer_on(\($0));", "if (!is_layer_locked(\($0))) { layer_off(\($0)); }") }
        case "TO": action.layer.map { ("layer_move(\($0));", nil) }
        case _ where isKeycode(action):
            ("register_code16(\(wrap(action.code, action.modifiers)));", "unregister_code16(\(wrap(action.code, action.modifiers)));")
        default: nil
        }
    }

    /// True for codes `register_code16` can send: HID keycodes (`KC_*`) and the locale codes `i18n.h` defines.
    static func isKeycode(_ action: KeyAction) -> Bool {
        action.macro == nil && (action.code.hasPrefix("KC_") || locale[action.code] != nil)
    }

    /// QMK's basic keycodes (`KC_A`…`KC_EXSEL`), the only taps `MT()` and `LT()` can carry.
    static func isBasic(_ code: String) -> Bool {
        let c = KeycodeCatalog.canonicalCode(code)
        return basic.contains(c) || c.wholeMatch(of: /KC_([A-Z0-9]|F[0-9]+|KP_\w+|INTERNATIONAL_[1-9]|LANGUAGE_[1-9])/) != nil
    }

    private static let basic: Set<String> = [
        "KC_ENTER", "KC_ESCAPE", "KC_BSPC", "KC_TAB", "KC_SPACE", "KC_MINUS", "KC_EQUAL", "KC_LBRC", "KC_RBRC", "KC_BSLS",
        "KC_NONUS_HASH", "KC_SCLN", "KC_QUOTE", "KC_GRAVE", "KC_COMMA", "KC_DOT", "KC_SLASH", "KC_CAPS", "KC_PSCR", "KC_SCRL",
        "KC_PAUSE", "KC_INSERT", "KC_HOME", "KC_PAGE_UP", "KC_DELETE", "KC_END", "KC_PGDN", "KC_RIGHT", "KC_LEFT", "KC_DOWN",
        "KC_UP", "KC_NUM_LOCK", "KC_NONUS_BACKSLASH", "KC_APPLICATION", "KC_FIND", "KC_UNDO", "KC_AGAIN", "KC_CUT", "KC_COPY",
        "KC_PASTE",
    ]

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
