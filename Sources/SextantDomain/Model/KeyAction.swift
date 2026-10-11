import Foundation

/// The eight USB modifiers, with left/right kept distinct (Oryx and QMK both distinguish them).
public struct Modifiers: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let leftControl = Self(rawValue: 1 << 0)
    public static let leftShift = Self(rawValue: 1 << 1)
    public static let leftOption = Self(rawValue: 1 << 2)
    public static let leftCommand = Self(rawValue: 1 << 3)
    public static let rightControl = Self(rawValue: 1 << 4)
    public static let rightShift = Self(rawValue: 1 << 5)
    public static let rightOption = Self(rawValue: 1 << 6)
    public static let rightCommand = Self(rawValue: 1 << 7)

    /// ⌃⌥⇧⌘ on the left side (QMK "Hyper").
    public static let hyper: Modifiers = [.leftControl, .leftOption, .leftShift, .leftCommand]
    /// ⌃⌥⇧ on the left side (QMK "Meh").
    public static let meh: Modifiers = [.leftControl, .leftOption, .leftShift]

    /// Either-side tests.
    public var hasControl: Bool { !intersection([.leftControl, .rightControl]).isEmpty }
    public var hasOption: Bool { !intersection([.leftOption, .rightOption]).isEmpty }
    public var hasShift: Bool { !intersection([.leftShift, .rightShift]).isEmpty }
    public var hasCommand: Bool { !intersection([.leftCommand, .rightCommand]).isEmpty }

    /// Mac glyphs in Apple's canonical order ⌃⌥⇧⌘ (side is not shown). Empty when no modifiers.
    public var glyphs: String {
        var s = ""
        if hasControl { s += "⌃" }
        if hasOption { s += "⌥" }
        if hasShift { s += "⇧" }
        if hasCommand { s += "⌘" }
        return s
    }

    /// Readable names, e.g. "Left Command + Left Shift".
    public var names: [String] {
        var out: [String] = []
        let pairs: [(Self, String)] = [
            (.leftControl, "Left Control"), (.leftOption, "Left Option"), (.leftShift, "Left Shift"), (.leftCommand, "Left Command"),
            (.rightControl, "Right Control"), (.rightOption, "Right Option"), (.rightShift, "Right Shift"),
            (.rightCommand, "Right Command"),
        ]
        for (m, n) in pairs where contains(m) { out.append(n) }
        return out
    }

    /// QMK `MOD_*` mask names, e.g. `["MOD_LGUI", "MOD_LSFT"]`.
    public var qmkMaskNames: [String] {
        if self == .hyper { return ["MOD_HYPR"] }
        if self == .meh { return ["MOD_MEH"] }
        let pairs: [(Self, String)] = [
            (.leftControl, "MOD_LCTL"), (.leftShift, "MOD_LSFT"), (.leftOption, "MOD_LALT"), (.leftCommand, "MOD_LGUI"),
            (.rightControl, "MOD_RCTL"), (.rightShift, "MOD_RSFT"), (.rightOption, "MOD_RALT"), (.rightCommand, "MOD_RGUI"),
        ]
        return pairs.filter { contains($0.0) }.map(\.1)
    }

    /// Parses a QMK `MOD_*` mask name (Oryx stores one in `KeyStep.modifier` for OSM / LM keys).
    public init?(qmkMask: String) {
        switch qmkMask {
        case "MOD_LCTL": self = .leftControl
        case "MOD_LSFT": self = .leftShift
        case "MOD_LALT": self = .leftOption
        case "MOD_LGUI": self = .leftCommand
        case "MOD_RCTL": self = .rightControl
        case "MOD_RSFT": self = .rightShift
        case "MOD_RALT": self = .rightOption
        case "MOD_RGUI": self = .rightCommand
        case "MOD_HYPR": self = .hyper
        case "MOD_MEH": self = .meh
        default: return nil
        }
    }

    /// Wraps a keycode in QMK modifier functions, e.g. `LGUI(LSFT(KC_LBRC))`.
    public func wrapQMK(_ inner: String) -> String {
        let pairs: [(Self, String)] = [
            (.leftControl, "LCTL"), (.leftShift, "LSFT"), (.leftOption, "LALT"), (.leftCommand, "LGUI"),
            (.rightControl, "RCTL"), (.rightShift, "RSFT"), (.rightOption, "RALT"), (.rightCommand, "RGUI"),
        ]
        var s = inner
        for (m, f) in pairs.reversed() where contains(m) { s = "\(f)(\(s))" }
        return s
    }
}

/// One step of a macro: press `code` with `modifiers`, then wait `delay` milliseconds.
public struct MacroStep: Hashable, Sendable {
    public var code: String
    public var modifiers: Modifiers
    /// Pause after this step, in milliseconds (Oryx allows 0...5000).
    public var delay: Int

    public init(code: String, modifiers: Modifiers = [], delay: Int = 0) {
        self.code = code
        self.modifiers = modifiers
        self.delay = delay
    }
}

/// A macro: an ordered list of up to 24 steps.
public struct Macro: Hashable, Sendable {
    public static let maxSteps = 24
    public var name: String?
    public var steps: [MacroStep]
    /// Press Enter after the last step.
    public var endsWithEnter: Bool
    /// Hold Option while typing (Oryx "send Unicode"; Windows-oriented).
    public var holdsOption: Bool

    public init(name: String? = nil, steps: [MacroStep], endsWithEnter: Bool = false, holdsOption: Bool = false) {
        self.name = name
        self.steps = steps
        self.endsWithEnter = endsWithEnter
        self.holdsOption = holdsOption
    }

    /// Sum of all step delays, in milliseconds.
    public var totalDelay: Int { steps.reduce(0) { $0 + $1.delay } }
}

/// What a key does in one slot (tap, hold, double-tap or tap-then-hold).
///
/// Mirrors Oryx's `KeyStep`. `code` is a QMK keycode name as Oryx stores it (modern names such as
/// `KC_LEFT_SHIFT`, `KC_PGDN`, `QK_BOOT`), or a layer function (`MO`, `TG`, `TO`, `TT`, `OSL`, `LM`)
/// with ``layer`` set, or an Oryx pseudo-code such as `RGB` (set colour, with ``color``).
public struct KeyAction: Hashable, Sendable {
    /// QMK keycode or function name.
    public var code: String
    /// Target layer index for layer functions; nil otherwise.
    public var layer: Int?
    /// Modifiers sent with ``code`` (e.g. ⌘⇧ + `KC_LBRC`), or the modifier parameter of `OSM` / `LM`.
    /// Oryx's separate `modifier` string (`MOD_LSFT`) is folded in here.
    public var modifiers: Modifiers
    /// A macro played by this slot. When set, ``code`` is usually `KC_TRANSPARENT`.
    public var macro: Macro?
    /// Colour for `RGB` set-colour keys.
    public var color: HexColor?
    /// Free-text description Oryx lets users attach (30 characters max).
    public var description: String?

    public init(
        code: String, layer: Int? = nil, modifiers: Modifiers = [], macro: Macro? = nil, color: HexColor? = nil, description: String? = nil
    ) {
        self.code = code
        self.layer = layer
        self.modifiers = modifiers
        self.macro = macro
        self.color = color
        self.description = description
    }

    /// Normalised code (aliases resolved through the catalog, e.g. `KC_LSFT` -> `KC_LEFT_SHIFT`).
    public var canonicalCode: String { KeycodeCatalog.canonicalCode(code) }

    public var isTransparent: Bool { canonicalCode == "KC_TRANSPARENT" && macro == nil }
    public var isNone: Bool { canonicalCode == "KC_NO" && macro == nil }
    /// True for MO / TG / TO / TT / OSL / LM / DF and layer lock.
    public var isLayerAction: Bool { KeycodeCatalog.layerFunctions.contains(canonicalCode) || canonicalCode == "QK_LLCK" }
    /// True for plain modifier keycodes, one-shot modifiers and Hyper/Meh.
    public var isModifier: Bool { KeycodeCatalog.modifierCodes.contains(canonicalCode) || canonicalCode == "OSM" }
    /// True for RGB / LED control codes, including `RGB` set-colour keys.
    public var isLEDControl: Bool { KeycodeCatalog.entry(for: canonicalCode)?.category == .lighting }

    // Common constructors.
    public static func code(_ code: String, modifiers: Modifiers = []) -> Self { Self(code: code, modifiers: modifiers) }
    public static func momentary(_ layer: Int) -> Self { Self(code: "MO", layer: layer) }
    public static func toggle(_ layer: Int) -> Self { Self(code: "TG", layer: layer) }
    public static func moveTo(_ layer: Int) -> Self { Self(code: "TO", layer: layer) }
    public static func oneShotLayer(_ layer: Int) -> Self { Self(code: "OSL", layer: layer) }
    public static func setColor(_ color: HexColor) -> Self { Self(code: "RGB", color: color) }
    public static let transparent = Self(code: "KC_TRANSPARENT")
    public static let none = Self(code: "KC_NO")
}
