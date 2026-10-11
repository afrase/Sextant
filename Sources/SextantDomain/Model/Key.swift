import Foundation

/// The four action slots a key can carry.
public enum KeySlot: String, CaseIterable, Hashable, Sendable, Codable, Identifiable {
    case tap, hold, doubleTap, tapHold
    public var id: String { rawValue }

    /// Short title, as the slot strip shows it (spec §5.1).
    public var title: String {
        switch self {
        case .tap: String(localized: "Tap")
        case .hold: String(localized: "Hold")
        case .doubleTap: String(localized: "Double tap")
        case .tapHold: String(localized: "Tap then hold")
        }
    }
}

/// What kind of key this is (spec §2.4 glossary, §4.4).
///
/// Classification order (first match wins), mirroring how Oryx colours keys:
/// 1. no actions, or only `KC_TRANSPARENT` → ``transparent`` (Oryx generates `KC_TRANSPARENT` for an all-null key)
/// 2. only `KC_NO` → ``disabled``
/// 3. any slot plays a macro → ``macro``
/// 4. has a custom label → ``label``
/// 5. double-tap or tap-then-hold set → ``tapDance``
/// 6. both tap and hold set → ``dualFunction`` (e.g. Return / hold for Sym+Num)
/// 7. the single action is a layer function → ``layer``; an RGB/LED code → ``lighting``;
///    a modifier (including hold-only modifiers) → ``modifier``; anything else → ``regular``.
public enum KeyKind: String, CaseIterable, Hashable, Sendable {
    case regular, modifier, dualFunction, layer, lighting, label, macro, tapDance, transparent, disabled

    /// Name used in the kind key and the inspector badge.
    public var title: String {
        switch self {
        case .regular: String(localized: "Regular")
        case .modifier: String(localized: "Modifier")
        case .dualFunction: String(localized: "Dual-function")
        case .layer: String(localized: "Layer")
        case .lighting: String(localized: "Lighting")
        case .label: String(localized: "Label")
        case .macro: String(localized: "Macro")
        case .tapDance: String(localized: "Tap dance")
        case .transparent: String(localized: "Transparent")
        case .disabled: String(localized: "Disabled")
        }
    }
}

/// One key on one layer. Mirrors Oryx's `Key` minus UI-state fields.
public struct Key: Hashable, Sendable {
    public var tap: KeyAction?
    public var hold: KeyAction?
    public var doubleTap: KeyAction?
    public var tapHold: KeyAction?
    /// User-written legend (Oryx limit: 10 characters). Never reaches the firmware.
    public var customLabel: String?
    /// Per-key LED colour on this layer.
    public var glowColor: HexColor?
    /// Per-key colour while Caps Lock is on (Oryx `lockGlowColor`; kept for round-trips).
    public var lockGlowColor: HexColor?
    /// Per-key tapping term as a signed delta in ms from the global value (Oryx convention); nil means the global value.
    public var tappingTerm: Int?

    public init(
        tap: KeyAction? = nil, hold: KeyAction? = nil, doubleTap: KeyAction? = nil, tapHold: KeyAction? = nil,
        customLabel: String? = nil, glowColor: HexColor? = nil, lockGlowColor: HexColor? = nil, tappingTerm: Int? = nil
    ) {
        self.tap = tap
        self.hold = hold
        self.doubleTap = doubleTap
        self.tapHold = tapHold
        self.customLabel = customLabel
        self.glowColor = glowColor
        self.lockGlowColor = lockGlowColor
        self.tappingTerm = tappingTerm
    }

    /// A key whose tap is `code`.
    public init(_ code: String, modifiers: Modifiers = []) {
        self.init(tap: KeyAction(code: code, modifiers: modifiers))
    }

    /// `KC_TRANSPARENT` (what Oryx generates for an empty key).
    public static let transparent = Key(tap: .transparent)
    /// `KC_NO`.
    public static let none = Key(tap: KeyAction.none)

    /// Get or set the action in a slot.
    public subscript(slot: KeySlot) -> KeyAction? {
        get {
            switch slot {
            case .tap: tap
            case .hold: hold
            case .doubleTap: doubleTap
            case .tapHold: tapHold
            }
        }
        set {
            switch slot {
            case .tap: tap = newValue
            case .hold: hold = newValue
            case .doubleTap: doubleTap = newValue
            case .tapHold: tapHold = newValue
            }
        }
    }

    /// Populated slots in tap, hold, double-tap, tap-then-hold order.
    public var filledSlots: [KeySlot] { KeySlot.allCases.filter { self[$0] != nil } }

    /// Every populated action, in slot order.
    public var actions: [(slot: KeySlot, action: KeyAction)] { KeySlot.allCases.compactMap { s in self[s].map { (s, $0) } } }

    /// True when the key falls through to lower layers (no actions, or only `KC_TRANSPARENT`).
    public var isTransparent: Bool {
        let filled = actions
        if filled.isEmpty { return true }
        return filled.count == 1 && filled[0].slot == .tap && filled[0].action.isTransparent && (customLabel ?? "").isEmpty
    }

    /// The key's kind; see ``KeyKind`` for the rules.
    public var kind: KeyKind {
        let filled = actions
        if isTransparent { return .transparent }
        if filled.count == 1, filled[0].action.isNone, (customLabel ?? "").isEmpty { return .disabled }
        if filled.contains(where: { $0.action.macro != nil }) { return .macro }
        if let l = customLabel, !l.isEmpty { return .label }
        if doubleTap != nil || tapHold != nil { return .tapDance }
        if tap != nil && hold != nil { return .dualFunction }
        guard let only = filled.first?.action else { return .transparent }
        if only.isLayerAction { return .layer }
        if only.isLEDControl { return .lighting }
        if only.isModifier { return .modifier }
        return .regular
    }

    /// Layer indices this key's actions point at (MO/TG/TO/TT/OSL/LM targets).
    public var referencedLayers: [Int] { actions.compactMap { $0.action.isLayerAction ? $0.action.layer : nil } }
}
