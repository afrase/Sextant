import Foundation

extension KeyAction {
    /// True when the action can run inside a tap dance, whose slots the firmware presses and releases from C: a key
    /// (`KC_` or a locale code), modifiers, or a momentary or go-to layer. A macro, a color key, a firmware key, and TG,
    /// TT, OSL, LM, DF or OSM can't. The generator's statements must agree (QMKGeneratorTests checks the catalog).
    public var runsInTapDance: Bool {
        guard macro == nil else { return false }
        switch canonicalCode {
        case "MO", "TO": return layer != nil
        default: return KeycodeCatalog.modifier(forCode: code) != nil || typesInTapDance
        }
    }

    /// True when the action can be a tap dance's tap, which the dance also types on three or more taps: a key.
    public var typesInTapDance: Bool {
        macro == nil && (code.hasPrefix("KC_") || KeycodeCatalog.entry(for: code)?.category == .international)
    }
}

extension Key {
    /// The slots of a tap dance (a key with a double tap or tap then hold) that the firmware can't build.
    public var slotsOutsideTapDance: [KeySlot] {
        guard doubleTap != nil || tapHold != nil else { return [] }
        return actions.filter { !$0.action.runsInTapDance || ($0.slot == .tap && !$0.action.typesInTapDance) }.map(\.slot)
    }
}
