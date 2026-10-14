import Foundation

extension Combo {
    /// Most keys a combo takes (Oryx's limit; spec §6.4). Fewer than 2 is an empty combo.
    public static let maxKeys = 6

    /// The layer whose keys the combo reads (ADR 0046). QMK matches combos by keycode, so the combo fires whenever keys
    /// with those keycodes go down together, on any layer; nil reads the base layer, as the generator does.
    public var keysLayer: Int { layer ?? 0 }
}

/// Combo edits (spec §6.4, ADR 0046). Each does nothing when there is no combo with the id.
extension KeyboardLayout {
    public func combo(id: String) -> Combo? { combos.first { $0.id == id } }

    /// Adds a combo at the end; its number is its position (Oryx numbers combos the same way).
    public mutating func addCombo(_ combo: Combo) { combos.append(combo) }

    public mutating func removeCombo(id: String) { combos.removeAll { $0.id == id } }

    public mutating func updateCombo(id: String, _ body: (inout Combo) -> Void) {
        guard let i = combos.firstIndex(where: { $0.id == id }) else { return }
        body(&combos[i])
    }

    /// Adds the key to the combo, or takes it out when it is in. Keys off the board, and a seventh key, are refused.
    public mutating func toggleComboKey(_ index: Int, in id: String) {
        guard (0..<keyCount).contains(index) else { return }
        updateCombo(id: id) { combo in
            if let at = combo.keyIndices.firstIndex(of: index) {
                combo.keyIndices.remove(at: at)
            } else if combo.keyIndices.count < Combo.maxKeys {
                combo.keyIndices.append(index)
            }
        }
    }

    /// Replaces the combo's keys, dropping repeats and keys off the board, in the order given.
    public mutating func setComboKeys(_ indices: [Int], in id: String) {
        var seen = Set<Int>()
        let keys = indices.filter { (0..<keyCount).contains($0) && seen.insert($0).inserted }
        updateCombo(id: id) { $0.keyIndices = keys }
    }

    /// The layer the combo reads its keys from; a layer that doesn't exist is ignored.
    public mutating func setComboLayer(_ layer: Int?, in id: String) {
        guard layer.map(layers.indices.contains) ?? true else { return }
        updateCombo(id: id) { $0.layer = layer }
    }

    public mutating func setComboOutput(_ output: KeyAction, in id: String) { updateCombo(id: id) { $0.output = output } }

    /// Names the combo; nil or blank clears the name.
    public mutating func renameCombo(id: String, to name: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        updateCombo(id: id) { $0.name = trimmed?.isEmpty == false ? trimmed : nil }
    }
}

extension LayoutIssues {
    /// The combo checks the generator can't express, or that won't fire as meant (spec §7.5): more than 6 keys, a key
    /// set another combo on the same layer has, keys that are transparent or tap dances on the combo's layer (QMK matches
    /// keycodes, so neither can match), and keys side by side in a row, which fast typing rolls across (a warning).
    /// Fewer than 2 keys is the empty-combo check's.
    static func comboIssues(_ layout: KeyboardLayout) -> [LayoutIssue] {
        let geometry = layout.board?.geometry()
        var issues: [LayoutIssue] = []
        let triggers = layout.combos.map { "\($0.keysLayer):\(Set($0.keyIndices).sorted())" }
        for (ci, combo) in layout.combos.enumerated() where combo.keyIndices.count >= 2 {
            func add(_ kind: LayoutIssue.Kind, _ severity: LayoutIssue.Severity = .error) {
                issues.append(LayoutIssue(kind: kind, severity: severity, key: nil, combo: combo.id))
            }
            if combo.keyIndices.count > Combo.maxKeys { add(.comboTooManyKeys(combo.keyIndices.count)) }
            if triggers.enumerated().contains(where: { $0.offset != ci && $0.element == triggers[ci] }) { add(.duplicateComboTrigger) }
            for index in combo.keyIndices {
                guard let key = layout.key(layer: combo.keysLayer, index: index) else { continue }
                if key.isTransparent {
                    add(.comboKeyTransparent(index))
                } else if key.isTapDance {
                    add(.comboKeyTapDance(index))
                }
            }
            if let pair = geometry?.rollingPair(combo.keyIndices) { add(.rollingNeighbors(pair.0, pair.1), .warning) }
        }
        return issues
    }
}

extension Key {
    /// A tap dance: a double tap or tap-then-hold makes the generator build the key as one (spec §6.5).
    var isTapDance: Bool { doubleTap != nil || tapHold != nil }
}

extension BoardGeometry {
    /// The first two keys of a combo whose keys a fast typist rolls across in one motion: all on one row of one half,
    /// each beside the next. Nil for any other set: a roll can't reach keys on two rows, or with a gap between them.
    public func rollingPair(_ indices: [Int]) -> (Int, Int)? {
        guard indices.count >= 2, indices.allSatisfy(keys.indices.contains) else { return nil }
        let shapes = indices.map { keys[$0] }.sorted { $0.column < $1.column }
        guard let first = shapes.first, shapes.allSatisfy({ $0.hand == first.hand && $0.cluster == first.cluster && $0.row == first.row })
        else { return nil }
        for (a, b) in zip(shapes, shapes.dropFirst()) where b.column - a.column != 1 { return nil }
        // Left to right on the board, as the issue names them ("J and K"): the right thumbs' columns run right to left.
        let (a, b) = (shapes[0], shapes[1])
        return a.center.x <= b.center.x ? (a.index, b.index) : (b.index, a.index)
    }
}
