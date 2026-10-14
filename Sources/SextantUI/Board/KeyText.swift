import Foundation
import SextantDomain

/// Words for keys and layers: the canvas readout (spec §3.7), context-strip lines and VoiceOver text (§4.11, §11).
enum KeyText {
    // MARK: VoiceOver

    /// Short label: "Return, hold for Sym+Num", "Z, inherited", "Reset".
    static func label(_ resolved: ResolvedLegend, index: Int) -> String {
        let legend = resolved.legend
        var parts = [legend.primary?.name ?? String(localized: "Key \(index)")]
        if legend.secondarySlot == .hold, let hold = legend.secondary {
            parts.append(String(localized: "hold for \(hold.layerName ?? hold.name)"))
        }
        if resolved.isInherited { parts.append(String(localized: "inherited")) }
        return parts.joined(separator: ", ")
    }

    /// Long value: what the key does, where it is, then what a board mode marks on it. "Dual-function. Tap sends
    /// Return. Hold activates layer 1, Sym+Num. Left thumb, key 24. Added."
    static func value(
        _ resolved: ResolvedLegend, layout: KeyboardLayout, layer: Int, index: Int, geometry: BoardGeometry,
        decoration: CapDecoration = CapDecoration()
    ) -> String {
        let marks = [decoration.badge?.accessibilityText, decoration.number?.accessibilityText, decoration.count?.accessibilityText]
            .compactMap { $0.map { "\($0)." } }
        return ([actionAndPlace(resolved, layout: layout, layer: layer, index: index, geometry: geometry)] + marks).joined(separator: " ")
    }

    private static func actionAndPlace(
        _ resolved: ResolvedLegend, layout: KeyboardLayout, layer: Int, index: Int, geometry: BoardGeometry
    ) -> String {
        let layerName = layout.layers[safe: layer]?.title ?? ""
        let what: String
        if resolved.isInherited, let primary = resolved.legend.primary {
            var acts = primary.name
            if resolved.legend.secondarySlot == .hold, let hold = resolved.legend.secondary {
                acts += String(localized: ", hold \(hold.layerName ?? hold.name)")
            }
            let source = resolved.sourceLayer.flatMap { layout.layers[safe: $0]?.title } ?? ""
            what = String(localized: "Transparent on \(layerName). Acts as \(acts), from \(source).")
        } else if resolved.ownKind == .transparent {
            what = String(localized: "Transparent on \(layerName). Nothing below it.")
        } else if resolved.ownKind == .disabled {
            what = String(localized: "Disabled. No action.")
        } else {
            let single = resolved.legend.slots.count == 1
            let sentences = KeySlot.allCases.compactMap { slot in
                resolved.legend.slots[slot].map { sentence(slot: slot, action: $0, single: single) }
            }
            what = ([resolved.ownKind.title + "."] + sentences).joined(separator: " ")
        }
        guard geometry.keys.indices.contains(index) else { return what }
        return "\(what) \(position(geometry.key(index), in: geometry)), \(String(localized: "key \(index)"))."
    }

    private static func sentence(slot: KeySlot, action: ActionLegend, single: Bool) -> String {
        if let layer = action.layer, slot == .hold, let name = action.layerName {
            return String(localized: "Hold activates layer \(layer), \(name).")
        }
        // Layer actions already carry their verb ("Hold for Sym+Num", "Toggle Brd+Sys").
        if single { return action.layer != nil ? "\(action.name)." : String(localized: "Sends \(action.name).") }
        switch slot {
        case .tap: return String(localized: "Tap sends \(action.name).")
        case .hold: return String(localized: "Hold sends \(action.name).")
        case .doubleTap: return String(localized: "Double tap sends \(action.name).")
        case .tapHold: return String(localized: "Tap then hold sends \(action.name).")
        }
    }

    /// "Left thumb, outer key", "Left hand, bottom row, column 2", "Right hand, top row, far right". Columns count
    /// from the left on both halves.
    static func position(_ shape: BoardGeometry.KeyShape, in geometry: BoardGeometry) -> String {
        let leftHand = shape.hand == .left
        if shape.cluster == .thumb {
            // Thumb column 1 is the key nearer the middle of the board.
            return switch (leftHand, shape.column == 1) {
            case (true, true): String(localized: "Left thumb, inner key")
            case (true, false): String(localized: "Left thumb, outer key")
            case (false, true): String(localized: "Right thumb, inner key")
            case (false, false): String(localized: "Right thumb, outer key")
            }
        }
        let main = geometry.keys.filter { $0.cluster == .main }
        let lastRow = main.map(\.row).max() ?? 0
        let hand = leftHand ? String(localized: "Left hand") : String(localized: "Right hand")
        let column =
            if leftHand && shape.column == 0 {
                String(localized: "far left")
            } else if !leftHand && shape.column == main.filter({ $0.hand == .right }).map(\.column).max() {
                String(localized: "far right")
            } else {
                String(localized: "column \(shape.column + 1)")
            }
        let row =
            if shape.row == 0 {
                String(localized: "top row")
            } else if shape.row == lastRow {
                String(localized: "bottom row")
            } else if shape.row == geometry.keys.first(where: \.isHomeRow)?.row {
                // By row, not the per-key flag, which is off for the outer pinky keys.
                String(localized: "home row")
            } else {
                String(localized: "row \(shape.row + 1)")
            }
        return "\(hand), \(row), \(column)"
    }

    // MARK: Flash mode (spec §7.3)

    /// Card A: where the reset button is, "on the top edge of the left half, above the 3 key", naming the key by what
    /// it shows on the base layer.
    static func resetButtonPlace(layout: KeyboardLayout, geometry: BoardGeometry) -> String {
        let index = (layout.board ?? .voyager).resetButtonKey
        guard geometry.keys.indices.contains(index) else { return String(localized: "on the top edge of the keyboard") }
        let shape = geometry.key(index)
        let half = shape.hand == .left ? String(localized: "left half") : String(localized: "right half")
        if let name = baseName(layout: layout, index: index) {
            return String(localized: "on the top edge of the \(half), above the \(name) key")
        }
        return String(localized: "on the top edge of the \(half), above the top-row key in column \(shape.column + 1)")
    }

    /// What a key shows on the base layer, the name people know it by ("3", "Space", "Nav"); nil for a transparent or
    /// disabled key.
    static func baseName(layout: KeyboardLayout, index: Int) -> String? {
        let resolved = Legends.legend(layout: layout, layer: 0, index: index)
        guard resolved.ownKind != .transparent, resolved.ownKind != .disabled, let primary = resolved.legend.primary else { return nil }
        return primary.layerName ?? CapLegendView.capText(for: primary)
    }

    /// Card B: one step of the way to the Reset key, naming the key by what it shows on the base layer and where it
    /// is: ("Hold Space", "Right thumb, outer key"), ("Press the key that shows “-” on Main", "Right hand, top row, far
    /// right").
    static func flashStep(_ key: KeyRef, isHold: Bool, layout: KeyboardLayout, geometry: BoardGeometry) -> (text: String, position: String)
    {
        let name = baseName(layout: layout, index: key.index)
        let main = layout.layers.first?.title ?? ""
        let text: String
        if key.layer == 0, let name {
            // The key does this on the base layer itself, so its own name says it.
            text = isHold ? String(localized: "Hold \(name)") : String(localized: "Press \(name)")
        } else if let name {
            text =
                isHold
                ? String(localized: "Hold the key that shows “\(name)” on \(main)")
                : String(localized: "Press the key that shows “\(name)” on \(main)")
        } else {
            text = isHold ? String(localized: "Hold the key") : String(localized: "Press the key")
        }
        return (text, geometry.keys.indices.contains(key.index) ? position(geometry.key(key.index), in: geometry) : "")
    }

    // MARK: Canvas

    /// What brings a layer up, for the readout: "held by ⏎ (key 24)". Nil when no key reaches the layer.
    static func activator(layout: KeyboardLayout, layer: Int) -> (text: String, layer: Int)? {
        guard let found = layout.keysActivating(layer: layer).first, let key = layout.key(layer: found.layer, index: found.index)
        else { return nil }
        let legend = Legends.legend(for: key, layerNames: layout.layerNames)
        let name = legend.primary.map(CapLegendView.capText) ?? ""
        let text =
            switch found.action.canonicalCode {
            case "TG", "TT": String(localized: "toggled by \(name) (key \(found.index))")
            case "TO", "DF": String(localized: "reached by \(name) (key \(found.index))")
            case "OSL": String(localized: "one-shot from \(name) (key \(found.index))")
            default: String(localized: "held by \(name) (key \(found.index))")
            }
        return (text, found.layer)
    }

    /// The canvas header readout (spec §3.7): "Layer 1 · held by ⏎ (key 24) · 47 own · 5 inherited".
    static func readout(layout: KeyboardLayout, layer: Int, isFollowing: Bool) -> String {
        if isFollowing { return String(localized: "LIVE · following the keyboard") }
        if layer == 0 { return String(localized: "Layer 0 · base · \(layout.keyCount) keys") }
        let own = layout.layers[safe: layer]?.keys.filter { !$0.isTransparent }.count ?? 0
        var parts = [String(localized: "Layer \(layer)")]
        if let activator = activator(layout: layout, layer: layer) { parts.append(activator.text) }
        parts.append(String(localized: "\(own) own"))
        parts.append(String(localized: "\(layout.keyCount - own) inherited"))
        return parts.joined(separator: " · ")
    }

    /// A context-strip card's line and its spoken form (spec §3.7, §11): "⏎ · hold Sym+Num", "Inherits ⏎", "Esc".
    static func stripLine(_ resolved: ResolvedLegend) -> (text: String, spoken: String) {
        let legend = resolved.legend
        guard let primary = legend.primary else { return (KeyKind.transparent.title, KeyKind.transparent.title) }
        let capText = CapLegendView.capText
        if resolved.isInherited {
            return (String(localized: "Inherits \(capText(primary))"), String(localized: "inherits \(primary.name)"))
        }
        switch resolved.ownKind {
        case .transparent, .disabled: return (resolved.ownKind.title, resolved.ownKind.title)
        default: break
        }
        if legend.secondarySlot == .hold, let hold = legend.secondary {
            return (
                String(localized: "\(capText(primary)) · hold \(hold.layerName ?? capText(hold))"),
                String(localized: "\(primary.name), hold for \(hold.layerName ?? hold.name)")
            )
        }
        return (capText(primary), primary.name)
    }

    /// The error capsule's text for a live issue (spec §3.7): "Unknown keycode on Brd+Sys · key 45 · Tap", "Empty
    /// combo · Combo 3".
    static func issueText(_ issue: LayoutIssue, layout: KeyboardLayout) -> String {
        let comboIndex = issue.combo.flatMap { id in layout.combos.firstIndex { $0.id == id } }
        /// A combo key by what it shows on the combo's layer ("J"), else (transparent through, or disabled) by its index.
        func member(_ index: Int) -> String {
            let legend = Legends.legend(layout: layout, layer: comboIndex.flatMap { layout.combos[$0].layer } ?? 0, index: index).legend
            guard legend.kind != .transparent, legend.kind != .disabled, let primary = legend.primary else { return "\(index)" }
            return primary.layerName ?? CapLegendView.capText(for: primary)
        }
        let what =
            switch issue.kind {
            case let .unknownKeycode(code): String(localized: "Unknown keycode \(code)")
            case let .missingLayer(n): String(localized: "Layer \(n) doesn't exist")
            case let .unreachableLayer(n): String(localized: "Layer \(n) can't be reached")
            case let .macroTooLong(steps): String(localized: "Macro has \(steps) steps")
            case let .macroStepNotTypable(step, code): String(localized: "Macro step \(step + 1) can't type \(code)")
            case .emptyCombo: String(localized: "Empty combo")
            case let .comboTooManyKeys(n): String(localized: "Combo has \(n) keys; 6 is the most")
            case .duplicateComboTrigger: String(localized: "Another combo uses the same keys")
            case let .comboKeyTransparent(i): String(localized: "Combo key \(member(i)) is transparent")
            case let .comboKeyDisabled(i): String(localized: "Combo key \(member(i)) is disabled")
            case let .comboKeyTapDance(i): String(localized: "Combo key \(member(i)) is a tap dance")
            case let .comboKeyRepeated(i): String(localized: "Combo key \(member(i)) types the same keycode as another")
            case let .rollingNeighbors(a, b): String(localized: "Keys \(member(a)) and \(member(b)) are rolling neighbors")
            // A flagged tap may run, but the dance also types it on three or more taps.
            case .notInTapDance where issue.key?.slot == .tap: String(localized: "A tap dance's tap must be a key")
            case .notInTapDance: String(localized: "Action can't run in a tap dance")
            case .tappingTermIgnored: String(localized: "Tapping term ignored (Per-key tapping term is off)")
            case .nearSizeLimit: String(localized: "Firmware is near the size limit")
            }
        if let i = comboIndex { return "\(what) · \(layout.combos[i].name ?? String(localized: "Combo \(i + 1)"))" }
        guard let key = issue.key else { return what }
        var parts = [String(localized: "\(what) on \(layout.layers[safe: key.layer]?.title ?? "")"), String(localized: "key \(key.index)")]
        if let slot = key.slot { parts.append(slot.title) }
        return parts.joined(separator: " · ")
    }
}
