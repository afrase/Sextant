import Foundation

/// The four action slots a key can carry.
public enum KeySlot: String, CaseIterable, Hashable, Sendable, Codable, Identifiable {
    case tap, hold, doubleTap, tapHold
    public var id: String { rawValue }

    /// Short, human title ("Tap", "Hold", "Double-tap", "Tap then hold").
    public var title: String {
        switch self {
        case .tap: "Tap"
        case .hold: "Hold"
        case .doubleTap: "Double-tap"
        case .tapHold: "Tap then hold"
        }
    }

    /// SF Symbol that suggests the gesture.
    public var symbolName: String {
        switch self {
        case .tap: "hand.tap"
        case .hold: "hand.point.down"
        case .doubleTap: "2.circle"
        case .tapHold: "hand.tap.fill"
        }
    }
}

/// What kind of key this is, for colour-coding and legends.
///
/// Classification order (first match wins), mirroring how Oryx colours keys:
/// 1. no actions, or only `KC_TRANSPARENT` → ``transparent``
/// 2. only `KC_NO` → ``none``
/// 3. any slot plays a macro → ``macro``
/// 4. has a custom label → ``customLabel``
/// 5. double-tap or tap-then-hold set → ``tapDance``
/// 6. both tap and hold set → ``multiFunction`` (e.g. Enter / hold for Sym+Num)
/// 7. the single action is a layer function → ``layerKey``; an RGB/LED code → ``ledControl``;
///    a modifier (including hold-only modifiers) → ``modifier``; anything else → ``regular``.
public enum KeyKind: String, CaseIterable, Hashable, Sendable, Codable {
    case regular, modifier, multiFunction, tapDance, ledControl, macro, customLabel, layerKey, transparent, none

    /// Neutral human title for legends and inspectors.
    public var title: String {
        switch self {
        case .regular: "Regular"
        case .modifier: "Modifier"
        case .multiFunction: "Tap + hold"
        case .tapDance: "Tap dance"
        case .ledControl: "Lighting"
        case .macro: "Macro"
        case .customLabel: "Custom label"
        case .layerKey: "Layer"
        case .transparent: "Transparent"
        case .none: "Disabled"
        }
    }

    /// One-line explanation, written for Sextant.
    public var explanation: String {
        switch self {
        case .regular: "Sends one keycode."
        case .modifier: "Shift, Control, Option or Command, possibly one-shot."
        case .multiFunction: "Does one thing when tapped and another when held."
        case .tapDance: "Also reacts to a double-tap or a tap followed by a hold."
        case .ledControl: "Controls the keyboard's lighting."
        case .macro: "Types a recorded sequence of keys."
        case .customLabel: "Shows a label you wrote instead of its keycode."
        case .layerKey: "Activates, toggles or switches to another layer."
        case .transparent: "Falls through to the key below it on a lower layer."
        case .none: "Does nothing on this layer."
        }
    }

    /// A suggested SF Symbol for legends of kinds (neutral; designers may ignore it).
    public var symbolName: String {
        switch self {
        case .regular: "character"
        case .modifier: "command"
        case .multiFunction: "hand.tap"
        case .tapDance: "hand.tap.fill"
        case .ledControl: "lightbulb"
        case .macro: "text.append"
        case .customLabel: "tag"
        case .layerKey: "square.3.layers.3d"
        case .transparent: "arrow.down.to.line"
        case .none: "nosign"
        }
    }
}

/// One key on one layer. Mirrors Oryx's `Key` minus UI-state fields.
public struct Key: Hashable, Sendable, Codable {
    public var tap: KeyAction?
    public var hold: KeyAction?
    public var doubleTap: KeyAction?
    public var tapHold: KeyAction?
    /// User-written legend (Oryx limit: 10 characters). Never reaches the firmware.
    public var customLabel: String?
    /// Per-key LED colour on this layer.
    public var glowColor: HexColor?
    /// Per-key tapping term in ms when per-key tapping term is enabled; nil means the global value.
    public var tappingTerm: Int?

    public init(tap: KeyAction? = nil, hold: KeyAction? = nil, doubleTap: KeyAction? = nil, tapHold: KeyAction? = nil,
                customLabel: String? = nil, glowColor: HexColor? = nil, tappingTerm: Int? = nil) {
        self.tap = tap
        self.hold = hold
        self.doubleTap = doubleTap
        self.tapHold = tapHold
        self.customLabel = customLabel
        self.glowColor = glowColor
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
    public var actions: [(slot: KeySlot, action: KeyAction)] { filledSlots.map { ($0, self[$0]!) } }

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
        if filled.count == 1, filled[0].action.isNone, (customLabel ?? "").isEmpty { return .none }
        if filled.contains(where: { $0.action.macro != nil }) { return .macro }
        if let l = customLabel, !l.isEmpty { return .customLabel }
        if doubleTap != nil || tapHold != nil { return .tapDance }
        if tap != nil && hold != nil { return .multiFunction }
        guard let only = filled.first?.action else { return .transparent }
        if only.isLayerAction { return .layerKey }
        if only.isLEDControl { return .ledControl }
        if only.isModifier { return .modifier }
        return .regular
    }

    /// Layer indices this key's actions point at (MO/TG/TO/TT/OSL/LM targets).
    public var referencedLayers: [Int] { actions.compactMap { $0.action.isLayerAction ? $0.action.layer : nil } }
}
