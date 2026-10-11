import SextantDomain

/// What a Hold or Tap then hold slot holds (spec §5.2): the segmented control's choices.
enum HoldMode: CaseIterable, Hashable {
    case modifier, layer, key, nothing

    init(_ action: KeyAction?) {
        guard let action else {
            self = .nothing
            return
        }
        if KeycodeCatalog.layerFunctions.contains(action.canonicalCode) {
            self = .layer
        } else if action.macro == nil, KeycodeCatalog.modifier(forCode: action.code) != nil {
            self = .modifier
        } else {
            self = .key
        }
    }

    var title: String {
        switch self {
        case .modifier: String(localized: "Modifier")
        case .layer: String(localized: "Layer")
        case .key: String(localized: "Key")
        case .nothing: String(localized: "Nothing")
        }
    }
}

extension KeyAction {
    /// The modifiers a modifier hold presses: its keycode's, plus any chorded with it (⌃⇧ is `KC_LEFT_CTRL` + Shift).
    var heldModifiers: Modifiers { (KeycodeCatalog.modifier(forCode: code) ?? []).union(modifiers) }

    /// A hold that presses `modifiers`, or nil for none. Hyper and Meh use Oryx's `ALL_T` / `MEH_T`; any other set is
    /// its first modifier's keycode chorded with the rest, which the generator builds as a dual-function key.
    static func holding(_ modifiers: Modifiers) -> KeyAction? {
        if modifiers == .hyper { return KeyAction(code: "ALL_T") }
        if modifiers == .meh { return KeyAction(code: "MEH_T") }
        let codes: [(Modifiers, String)] = [
            (.leftControl, "KC_LEFT_CTRL"), (.leftShift, "KC_LEFT_SHIFT"), (.leftOption, "KC_LEFT_ALT"), (.leftCommand, "KC_LEFT_GUI"),
            (.rightControl, "KC_RIGHT_CTRL"), (.rightShift, "KC_RIGHT_SHIFT"), (.rightOption, "KC_RIGHT_ALT"),
            (.rightCommand, "KC_RIGHT_GUI"),
        ]
        guard let (first, code) = codes.first(where: { modifiers.contains($0.0) }) else { return nil }
        return KeyAction(code: code, modifiers: modifiers.subtracting(first))
    }
}

extension Modifiers {
    /// The ⌃ ⌥ ⇧ ⌘ columns of the modifier toggles, each as its left and right modifier.
    static let columns: [(glyph: String, left: Modifiers, right: Modifiers)] = [
        ("⌃", .leftControl, .rightControl), ("⌥", .leftOption, .rightOption), ("⇧", .leftShift, .rightShift),
        ("⌘", .leftCommand, .rightCommand),
    ]

    /// True when every modifier is a right-hand one (the Hold editor's Left / Right control).
    var isRightSided: Bool { !isEmpty && rawValue & 0x0F == 0 }

    /// The same modifiers, all on one side. Right-hand bits are the left-hand ones shifted up by four.
    func onSide(right: Bool) -> Modifiers {
        let left = (rawValue | rawValue >> 4) & 0x0F
        return Modifiers(rawValue: right ? left << 4 : left)
    }
}

extension KeyText {
    /// Layer behaviours a layer key can take (spec §5.3). `LM` stays editable on keys that already use it.
    static func layerBehaviours(current: String) -> [(code: String, title: String)] {
        let all = [
            ("MO", String(localized: "Hold")), ("TG", String(localized: "Toggle")), ("TO", String(localized: "Go to")),
            ("TT", String(localized: "Tap-toggle")), ("OSL", String(localized: "One-shot")), ("DF", String(localized: "Base layer")),
        ]
        return current == "LM" ? all + [("LM", String(localized: "Hold + mods"))] : all
    }

    /// Why a layer key on `own` won't do what it seems to (spec §5.3), or nil.
    static func layerWarning(code: String, target: Int, own: Int, layout: KeyboardLayout) -> String? {
        let name = { (layer: Int) in layout.layers[safe: layer]?.title ?? String(localized: "Layer \(layer)") }
        if target == own { return String(localized: "This is the key's own layer, so the key changes nothing.") }
        // QMK shows the highest active layer: a lower one turned on from here stays hidden wherever this layer has a key.
        if target < own, !["TO", "DF"].contains(code) {
            return String(localized: "\(name(target)) is below \(name(own)), so \(name(own))'s own keys still win while both are on.")
        }
        return nil
    }

    /// The transparent callout (spec §4.6, §5.1): "Transparent on Sym+Num. Acts as Z (hold ⌥) from Main."
    static func inheritance(_ resolved: ResolvedLegend, layout: KeyboardLayout, layer: Int) -> String {
        let here = layout.layers[safe: layer]?.title ?? ""
        guard resolved.isInherited, let primary = resolved.legend.primary else {
            return String(localized: "Transparent on \(here). Nothing below it, so it does nothing.")
        }
        let tap = CapLegendView.capText(for: primary)
        let source = resolved.sourceLayer.flatMap { layout.layers[safe: $0]?.title } ?? ""
        if resolved.legend.secondarySlot == .hold, let hold = resolved.legend.secondary {
            let held = hold.layerName ?? CapLegendView.capText(for: hold)
            return String(localized: "Transparent on \(here). Acts as \(tap) (hold \(held)) from \(source).")
        }
        return String(localized: "Transparent on \(here). Acts as \(tap) from \(source).")
    }

    /// The inspector's summary sentence (spec §5.1, §6.5): "Tap sends Return. Hold activates Sym+Num (MO(1))."
    static func summary(_ key: Key, layerNames: [String]) -> String {
        // A transparent tap under a hold shows as empty in the slot strip, so it isn't described either.
        key.actions.filter { !$0.action.isTransparent }.map { slot, action in
            let legend = Legends.legend(for: action, layerNames: layerNames)
            if KeycodeCatalog.layerFunctions.contains(action.canonicalCode) {
                if slot == .hold, action.canonicalCode == "MO", let name = legend.layerName {
                    return String(localized: "Hold activates \(name) (\(legend.qmk)).")
                }
                return String(localized: "\(slot.title): \(legend.name) (\(legend.qmk)).")
            }
            if slot == .hold || slot == .tapHold, HoldMode(action) == .modifier {
                let mods = action.heldModifiers
                let names = mods == .hyper ? "Hyper" : mods == .meh ? "Meh" : mods.names.joined(separator: " + ")
                return slot == .hold ? String(localized: "Hold for \(names).") : String(localized: "Tap then hold for \(names).")
            }
            return String(localized: "\(slot.title) sends \(legend.name).")
        }
        .joined(separator: " ")
    }
}
