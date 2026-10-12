import Foundation

/// A problem found in a layout before any build (spec §7.5 "Live issues").
public struct LayoutIssue: Hashable, Sendable, Identifiable {
    public enum Severity: String, Hashable, Sendable { case error, warning }
    /// The v1 kinds come ahead of the checks that raise them, which each feature adds (docs/v1-plan.md, rule 7).
    public enum Kind: Hashable, Sendable {
        case unknownKeycode(String)
        case missingLayer(Int)
        case unreachableLayer(Int)
        case macroTooLong(steps: Int)
        /// A macro step (0-based) that `SEND_STRING` can't type: its code has no `X_` name.
        case macroStepNotTypable(step: Int, code: String)
        case emptyCombo
        /// A combo with more than 6 keys; fewer than 2 is `emptyCombo`.
        case comboTooManyKeys(Int)
        /// Another combo on the same layer has the same keys.
        case duplicateComboTrigger
        /// The combo key at this board index is transparent; QMK matches combos by keycode, so it can't fire.
        case comboKeyTransparent(Int)
        /// The combo key at this board index is a tap dance, whose keycode a combo can't match either.
        case comboKeyTapDance(Int)
        /// Two combo keys (board indices) sit side by side, so fast typing may roll across them (a warning).
        case rollingNeighbors(Int, Int)
        /// A tap dance slot whose action can't run inside a dance.
        case notInTapDance
        /// A key's own tapping term, which the firmware ignores while per-key terms are off (a warning).
        case tappingTermIgnored
        case nearSizeLimit
    }

    public var kind: Kind
    public var severity: Severity
    /// The key the issue is on; nil for layout-wide issues (an unreachable layer, a combo).
    public var key: KeyRef?
    /// The id of the combo the issue is on.
    public var combo: String?

    public init(kind: Kind, severity: Severity, key: KeyRef?, combo: String? = nil) {
        self.kind = kind
        self.severity = severity
        self.key = key
        self.combo = combo
    }

    public var id: String {
        "\(kind)-\(key.map { "\($0.layer)-\($0.index)-\($0.slot?.rawValue ?? "")" } ?? "")-\(combo ?? "")"
    }
}

public enum LayoutIssues {
    /// Every live issue in `layout`, errors first, then in layer and key order. The generator builds tap dances, so
    /// they raise no issue; the size estimate needs a build, so the build reports it.
    public static func check(_ layout: KeyboardLayout) -> [LayoutIssue] {
        var issues: [LayoutIssue] = []
        var seen: Set<LayoutIssue> = []
        func add(_ kind: LayoutIssue.Kind, _ key: KeyRef?, _ severity: LayoutIssue.Severity = .error, combo: String? = nil) {
            let issue = LayoutIssue(kind: kind, severity: severity, key: key, combo: combo)
            if seen.insert(issue).inserted { issues.append(issue) }
        }
        func check(_ action: KeyAction, _ key: KeyRef?, combo: String? = nil) {
            let codes = [action.code] + (action.macro?.steps.map(\.code) ?? [])
            for code in codes where KeycodeCatalog.entry(for: code) == nil { add(.unknownKeycode(code), key, combo: combo) }
            if KeycodeCatalog.layerFunctions.contains(action.canonicalCode), !layout.layers.indices.contains(action.layer ?? -1) {
                add(.missingLayer(action.layer ?? -1), key, combo: combo)
            }
            // Oryx's editor limit, not the firmware's: Oryx built a 25-step macro (JRGQm), so this only warns.
            if let steps = action.macro?.steps.count, steps > Macro.maxSteps {
                add(.macroTooLong(steps: steps), key, .warning, combo: combo)
            }
        }
        for (li, layer) in layout.layers.enumerated() {
            for (ki, key) in layer.keys.enumerated() {
                for (slot, action) in key.actions { check(action, KeyRef(layer: li, index: ki, slot: slot)) }
            }
        }
        for combo in layout.combos {
            if combo.keyIndices.count < 2 || combo.output.isTransparent || combo.output.isNone {
                add(.emptyCombo, nil, combo: combo.id)
            } else {
                check(combo.output, nil, combo: combo.id)
            }
        }
        for issue in macroStepIssues(layout) { add(issue.kind, issue.key, combo: issue.combo) }
        let reachable = reachableLayers(layout)
        for li in layout.layers.indices where !reachable.contains(li) { add(.unreachableLayer(li), nil, .warning) }
        func rank(_ i: (offset: Int, element: LayoutIssue)) -> [Int] {
            [i.element.severity == .error ? 0 : 1, i.element.key?.layer ?? .max, i.element.key?.index ?? .max, i.offset]
        }
        return issues.enumerated().sorted { rank($0).lexicographicallyPrecedes(rank($1)) }.map(\.element)
    }

    /// Layers some chain of layer keys (or combos, or the Navigator's automouse) reaches from layer 0.
    static func reachableLayers(_ layout: KeyboardLayout) -> Set<Int> {
        var reached: Set<Int> = [0]
        if layout.navigator != nil, let auto = layout.automouseLayer { reached.insert(auto) }
        var queue = Array(reached)
        while let li = queue.popLast() {
            guard layout.layers.indices.contains(li) else { continue }
            let actions =
                layout.layers[li].keys.flatMap { $0.actions.map(\.action) }
                + layout.combos.filter { $0.layer == nil || $0.layer == li }.map(\.output)
            for action in actions where KeycodeCatalog.layerFunctions.contains(action.canonicalCode) {
                if let target = action.layer, reached.insert(target).inserted { queue.append(target) }
            }
        }
        return reached
    }
}
