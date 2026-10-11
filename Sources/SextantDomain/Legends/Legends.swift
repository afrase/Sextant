import Foundation

/// How to draw one action on a keycap.
public struct ActionLegend: Hashable, Sendable {
    /// Short keycap text: a character, Mac glyph(s) or short word. Includes modifier glyphs for chords ("⇧⌘[").
    public var text: String
    /// SF Symbol name, when a good one exists (draw it instead of, or beside, ``text``).
    public var symbol: String?
    /// Full readable name ("Left Command", "Hold for Sym+Num", "⇧⌘[ (Previous Tab)").
    public var name: String
    /// Left/right for side-specific modifiers; draw as a small L/R mark.
    public var side: ModifierSide?
    /// Modifiers chorded with the code (already included in ``text`` as glyphs).
    public var modifiers: Modifiers
    /// Target layer for layer actions.
    public var layer: Int?
    /// Target layer title for layer actions.
    public var layerName: String?
    /// Colour for `RGB` set-colour keys.
    public var color: HexColor?
    /// QMK expression for an "advanced" view, e.g. `KC_A`, `MO(1)`, `LGUI(LSFT(KC_LBRC))`.
    public var qmk: String
    /// Catalog category, when known.
    public var category: KeycodeCategory?
    /// True when the code isn't in the catalog (render as-is, maybe flagged).
    public var isUnknown: Bool
}

/// Everything needed to draw one key's legends.
public struct KeyLegend: Hashable, Sendable {
    public var kind: KeyKind
    /// Big legend. For custom-labelled keys its text is the custom label.
    public var primary: ActionLegend?
    /// Small legend: the hold action under a tap (e.g. "⌥" under "Z"), or the tap of a tap dance's second slot.
    public var secondary: ActionLegend?
    public var primarySlot: KeySlot?
    public var secondarySlot: KeySlot?
    /// The underlying action's text for a custom-labelled key ("⌘[" under "Back"). Nil otherwise.
    public var annotation: String?
    /// Every populated slot.
    public var slots: [KeySlot: ActionLegend]
    /// Whole-key QMK expression: `LT(1, KC_ENTER)`, `MT(MOD_LALT, KC_Z)`, `TD(…)`, `KC_A`.
    public var qmk: String
    /// Colour swatch for set-colour keys or the key's own glow colour.
    public var swatch: HexColor?
}

/// A legend after transparent resolution: what to draw at a position on a layer.
public struct ResolvedLegend: Hashable, Sendable {
    /// Legend of the effective key.
    public var legend: KeyLegend
    /// True when the key on this layer is transparent and the legend comes from a lower layer (draw dimmed).
    public var isInherited: Bool
    /// Layer the legend comes from.
    public var sourceLayer: Int?
    /// The kind of the key as stored on this layer (`.transparent` when inherited).
    public var ownKind: KeyKind
    /// True when this key holds the displayed layer active (Oryx hatches it).
    public var activatesDisplayedLayer: Bool
}

/// Legend formatting. Uses ``KeycodeCatalog`` for labels and SF Symbols.
public enum Legends {
    /// Legend for a key. Pass `layerNames` (e.g. `layout.layerNames`) to name layer targets.
    public static func legend(for key: Key, layerNames: [String] = []) -> KeyLegend {
        var slots: [KeySlot: ActionLegend] = [:]
        for (slot, action) in key.actions { slots[slot] = legend(for: action, layerNames: layerNames) }
        let kind = key.kind
        var primarySlot: KeySlot?
        var secondarySlot: KeySlot?
        let order = key.filledSlots
        if let tap = key.tap, !(tap.isTransparent && key.hold != nil) {
            primarySlot = .tap
            secondarySlot = order.first { $0 != .tap }
        } else {
            primarySlot = order.first { $0 != .tap } ?? order.first
            secondarySlot = order.first { $0 != primarySlot && $0 != .tap }
        }
        var primary = primarySlot.flatMap { slots[$0] }
        let secondary = secondarySlot.flatMap { slots[$0] }
        var annotation: String?
        if let label = key.customLabel, !label.isEmpty {
            annotation = primary?.text
            let underlying = primary?.name
            primary = ActionLegend(
                text: label, symbol: nil, name: underlying.map { "\(label) (\($0))" } ?? label,
                side: nil, modifiers: primary?.modifiers ?? [], layer: primary?.layer, layerName: primary?.layerName,
                color: primary?.color, qmk: primary?.qmk ?? "KC_NO", category: primary?.category, isUnknown: false)
        }
        return KeyLegend(
            kind: kind, primary: primary, secondary: secondary, primarySlot: primarySlot, secondarySlot: secondarySlot,
            annotation: annotation, slots: slots, qmk: qmkExpression(for: key),
            swatch: key.tap?.color ?? key.glowColor)
    }

    /// Legend for a key on a layer of `layout`, following transparency (see ``KeyboardLayout/resolvedKey(layer:index:activeLayers:)``).
    public static func legend(layout: KeyboardLayout, layer: Int, index: Int, activeLayers: Set<Int>? = nil) -> ResolvedLegend {
        let r = layout.resolvedKey(layer: layer, index: index, activeLayers: activeLayers)
        let activates = layer > 0 && (layout.key(layer: 0, index: index)?.referencedLayers.contains(layer) ?? false)
        return ResolvedLegend(
            legend: legend(for: r.effective, layerNames: layout.layerNames), isInherited: r.isInherited,
            sourceLayer: r.sourceLayer, ownKind: r.own.kind, activatesDisplayedLayer: activates)
    }

    /// Legend for one action.
    public static func legend(for action: KeyAction, layerNames: [String] = []) -> ActionLegend {
        let code = action.canonicalCode
        let entry = KeycodeCatalog.entry(for: code)
        let mods = action.modifiers

        // Macros.
        if let macro = action.macro {
            let name = macro.name ?? "Macro"
            return ActionLegend(
                text: macro.name ?? "Macro", symbol: "text.append", name: "\(name) (\(macro.steps.count) steps)",
                side: nil, modifiers: [], layer: nil, layerName: nil, color: nil, qmk: "MACRO", category: nil, isUnknown: false)
        }

        // Layer functions.
        if KeycodeCatalog.layerFunctions.contains(code) {
            let l = action.layer ?? 0
            let lname = layerNames.indices.contains(l) ? layerNames[l] : "Layer \(l)"
            let (verb, sym): (String, String) =
                switch code {
                case "MO": ("Hold for", "square.stack.3d.up")
                case "TG": ("Toggle", "square.stack.3d.up.fill")
                case "TO": ("Switch to", "arrow.right.square")
                case "TT": ("Tap-toggle", "square.stack.3d.down.right")
                case "OSL": ("One-shot", "1.square")
                case "LM": ("Hold for", "square.stack.3d.up")
                case "DF": ("Base layer:", "house")
                default: ("Layer", "square.3.layers.3d")
                }
            let modText = code == "LM" && !mods.isEmpty ? " + \(mods.glyphs)" : ""
            let qmk = code == "LM" ? "LM(\(l), \(mods.qmkMaskNames.joined(separator: " | ")))" : "\(code)(\(l))"
            return ActionLegend(
                text: lname + modText, symbol: sym, name: "\(verb) \(lname)\(modText)", side: nil, modifiers: code == "LM" ? mods : [],
                layer: l, layerName: lname, color: nil, qmk: qmk, category: .layers, isUnknown: false)
        }

        // One-shot modifier.
        if code == "OSM" {
            let side: ModifierSide? =
                mods.isSubset(of: [.leftControl, .leftShift, .leftOption, .leftCommand])
                ? .left
                : mods.isSubset(of: [.rightControl, .rightShift, .rightOption, .rightCommand]) ? .right : nil
            return ActionLegend(
                text: mods.glyphs.isEmpty ? "OSM" : mods.glyphs, symbol: mods == [.leftShift] || mods == [.rightShift] ? "shift" : nil,
                name: "One-shot \(mods.names.joined(separator: " + "))", side: side, modifiers: mods, layer: nil, layerName: nil,
                color: nil, qmk: "OSM(\(mods.qmkMaskNames.joined(separator: " | ")))", category: .modifiers, isUnknown: false)
        }

        // Set-colour key.
        if code == "RGB" {
            let hex = action.color?.hex ?? "#000000"
            return ActionLegend(
                text: "Colour", symbol: entry?.symbol, name: "Set colour \(hex)", side: nil, modifiers: [], layer: nil, layerName: nil,
                color: action.color, qmk: "RGB(\(hex))", category: .lighting, isUnknown: false)
        }

        // Plain or chorded keycode.
        let baseText = entry?.label ?? prettyUnknown(code)
        let text = mods.isEmpty ? baseText : mods.glyphs + baseText
        var name = entry?.name ?? code
        if !mods.isEmpty { name = "\(mods.glyphs)\(baseText) (\(mods.names.joined(separator: " + ")) + \(entry?.name ?? code))" }
        if let d = action.description, !d.isEmpty { name += " – \(d)" }
        let qmk = mods.isEmpty ? code : mods.wrapQMK(code)
        return ActionLegend(
            text: text, symbol: mods.isEmpty ? entry?.symbol : nil, name: name, side: mods.isEmpty ? entry?.side : nil, modifiers: mods,
            layer: nil, layerName: nil, color: nil, qmk: qmk, category: entry?.category, isUnknown: entry == nil)
    }

    /// QMK-style expression for a whole key, for an "advanced" legend view.
    public static func qmkExpression(for key: Key) -> String {
        if key.isTransparent { return "KC_TRNS" }
        if key.doubleTap != nil || key.tapHold != nil || key.actions.contains(where: { $0.action.macro != nil }) {
            let parts = key.actions.map { "\($0.slot.rawValue): \(legend(for: $0.action).qmk)" }
            return "TD(\(parts.joined(separator: ", ")))"
        }
        if let tap = key.tap, let hold = key.hold {
            let t = legend(for: tap).qmk
            if hold.isLayerAction, hold.canonicalCode == "MO", let l = hold.layer { return "LT(\(l), \(t))" }
            if let m = KeycodeCatalog.modifier(forCode: hold.canonicalCode) {
                if m == .hyper { return "ALL_T(\(t))" }
                if m == .meh { return "MEH_T(\(t))" }
                return "MT(\(m.qmkMaskNames.joined(separator: " | ")), \(t))"
            }
            return "DUAL(\(t), \(legend(for: hold).qmk))"
        }
        if let only = key.tap ?? key.hold { return legend(for: only).qmk }
        return "KC_NO"
    }

    static func prettyUnknown(_ code: String) -> String {
        var s = code
        for p in ["KC_", "QK_"] where s.hasPrefix(p) { s.removeFirst(p.count) }
        return s.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
