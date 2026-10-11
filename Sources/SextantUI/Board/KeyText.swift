import Foundation
import SextantDomain

/// Words for keys and layers: the canvas readout (spec §3.7), context-strip lines and VoiceOver text (§4.11, §11).
enum KeyText {
    /// The text a cap draws for an action ("⏎", "Space", "Esc").
    static func capText(_ action: ActionLegend) -> String { CapLegendView.capText(for: action) }

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

    /// Long value: what the key does, then where it is. "Dual-function. Tap sends Return. Hold activates layer 1,
    /// Sym+Num. Left thumb, key 24."
    static func value(layout: KeyboardLayout, layer: Int, index: Int, geometry: BoardGeometry) -> String {
        let resolved = Legends.legend(layout: layout, layer: layer, index: index)
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

    /// "Left thumb", "Left hand, bottom row, column 2".
    static func position(_ shape: BoardGeometry.KeyShape, in geometry: BoardGeometry) -> String {
        let leftHand = shape.hand == .left
        if shape.cluster == .thumb { return leftHand ? String(localized: "Left thumb") : String(localized: "Right thumb") }
        let lastRow = geometry.keys.filter { $0.cluster == .main }.map(\.row).max() ?? 0
        let row =
            if shape.row == 0 {
                String(localized: "top row")
            } else if shape.row == lastRow {
                String(localized: "bottom row")
            } else if shape.isHomeRow {
                String(localized: "home row")
            } else {
                String(localized: "row \(shape.row + 1)")
            }
        let hand = leftHand ? String(localized: "Left hand") : String(localized: "Right hand")
        return "\(hand), \(row), \(String(localized: "column \(shape.column + 1)"))"
    }

    // MARK: Canvas

    /// What brings a layer up, for the readout: "held by ⏎ (key 24)". Nil when no key reaches the layer.
    static func activator(layout: KeyboardLayout, layer: Int) -> (text: String, layer: Int)? {
        guard let found = layout.keysActivating(layer: layer).first, let key = layout.key(layer: found.layer, index: found.index)
        else { return nil }
        let legend = Legends.legend(for: key, layerNames: layout.layerNames)
        let name = legend.primary.map(capText) ?? ""
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

    /// The error capsule's text for a live issue (spec §3.7): "Unknown keycode on Brd+Sys · key 45 · Tap".
    static func issueText(_ issue: LayoutIssue, layout: KeyboardLayout) -> String {
        let what =
            switch issue.kind {
            case let .unknownKeycode(code): String(localized: "Unknown keycode \(code)")
            case let .missingLayer(n): String(localized: "Layer \(n) doesn't exist")
            case let .unreachableLayer(n): String(localized: "Layer \(n) can't be reached")
            case let .macroTooLong(steps): String(localized: "Macro has \(steps) steps")
            case .emptyCombo: String(localized: "Empty combo")
            case .tapDanceUnsupported: String(localized: "Tap dance can't be built yet")
            case .nearSizeLimit: String(localized: "Firmware is near the size limit")
            }
        guard let key = issue.key else { return what }
        var parts = [String(localized: "\(what) on \(layout.layers[safe: key.layer]?.title ?? "")"), String(localized: "key \(key.index)")]
        if let slot = key.slot { parts.append(slot.title) }
        return parts.joined(separator: " · ")
    }
}
