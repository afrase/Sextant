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
    /// The combo checks the generator can't express, or that won't fire as meant (spec §7.5): more than 6 keys, keycodes
    /// another combo listens for too (QMK matches keycodes, so only one of the two can fire), a key a combo can't use on
    /// the combo's layer (``Key/comboRefusal``), two keys typing one keycode (``KeyboardLayout/comboRepeatedKey(_:)``),
    /// and keys side by side in a row, which fast typing rolls across (a warning). Fewer than 2 keys is the empty-combo
    /// check's.
    static func comboIssues(_ layout: KeyboardLayout) -> [LayoutIssue] {
        let geometry = layout.board?.geometry()
        var issues: [LayoutIssue] = []
        let triggers = layout.combos.map { layout.comboTrigger($0) }
        for (ci, combo) in layout.combos.enumerated() where combo.keyIndices.count >= 2 {
            func add(_ kind: LayoutIssue.Kind, _ severity: LayoutIssue.Severity = .error) {
                issues.append(LayoutIssue(kind: kind, severity: severity, key: nil, combo: combo.id))
            }
            if combo.keyIndices.count > Combo.maxKeys { add(.comboTooManyKeys(combo.keyIndices.count)) }
            if triggers.enumerated().contains(where: { $0.offset != ci && $0.element == triggers[ci] }) { add(.duplicateComboTrigger) }
            for index in combo.keyIndices {
                switch layout.key(layer: combo.keysLayer, index: index)?.comboRefusal {
                case .transparent?: add(.comboKeyTransparent(index))
                case .disabled?: add(.comboKeyDisabled(index))
                case .tapDance?: add(.comboKeyTapDance(index))
                case nil: break
                }
            }
            if let index = layout.comboRepeatedKey(combo) { add(.comboKeyRepeated(index)) }
            if let pair = geometry?.rollingPair(combo.keyIndices) { add(.rollingNeighbors(pair.0, pair.1), .warning) }
        }
        return issues
    }
}

/// What a combo's key listens for: the keycode the generator writes for it, which every key written the same way shares,
/// else the key itself (a dual-function key QMK can't write as one keycode, or a macro, which the generator numbers per
/// key). Aliases count as their canonical code: QMK defines them as the same keycode.
private enum ComboListens: Hashable {
    case action(KeyAction)
    case modTapOrLayerTap(tap: KeyAction, hold: KeyAction)
    case key(layer: Int, index: Int)
}

extension KeyboardLayout {
    /// The first key of the combo that types the keycode an earlier key of it types: QMK finds both presses at one
    /// place in the combo, so the combo never sees all its keys down. Keys a combo can't use (``Key/comboRefusal``)
    /// have their own issue and don't count. Nil when every key listens for its own. The live issue and the generator
    /// both use it (ADR 0046).
    public func comboRepeatedKey(_ combo: Combo) -> Int? {
        var seen = Set<ComboListens>()
        return combo.keyIndices.first { index in
            guard key(layer: combo.keysLayer, index: index)?.comboRefusal == nil else { return false }
            return !seen.insert(comboListens(layer: combo.keysLayer, index: index)).inserted
        }
    }

    /// The combo's keycodes, as a count of each, so two combos that listen for the same ones compare equal whichever
    /// layer or spots they read them from.
    fileprivate func comboTrigger(_ combo: Combo) -> [ComboListens: Int] {
        var counts: [ComboListens: Int] = [:]
        for index in combo.keyIndices { counts[comboListens(layer: combo.keysLayer, index: index), default: 0] += 1 }
        return counts
    }

    private func comboListens(layer: Int, index: Int) -> ComboListens {
        guard let key = key(layer: layer, index: index), !key.isTapDance else { return .key(layer: layer, index: index) }
        switch (key.tap, key.hold) {
        case let (tap?, hold?) where Key.isModTapOrLayerTap(tap: tap, hold: hold):
            return .modTapOrLayerTap(tap: tap.canonical, hold: hold.canonical)
        case let (only?, nil) where only.macro == nil, let (nil, only?) where only.macro == nil: return .action(only.canonical)
        default: return .key(layer: layer, index: index)
        }
    }
}

extension KeyAction {
    /// The action as a keycode: its catalog code, so aliases (`KC_ENT`, `KC_ENTER`) compare equal, and no description,
    /// which the firmware never sees.
    fileprivate var canonical: KeyAction {
        var action = self
        action.code = canonicalCode
        action.description = nil
        return action
    }
}

extension Key {
    /// Why a combo can't use this key (ADR 0046), the rule the live issues and the generator share.
    public enum ComboRefusal: Sendable {
        /// The generator writes KC_TRANSPARENT, which the firmware never reports as pressed: it reports the key below.
        case transparent
        /// KC_NO is COMBO_END, which would end the combo's key list early.
        case disabled
        /// Oryx refuses tap dances in combos; Sextant keeps its rule.
        case tapDance
    }

    /// Nil when a combo can use the key. A key with one of tap and hold is written as that action's keycode, an empty
    /// key as transparent, whatever its label.
    public var comboRefusal: ComboRefusal? {
        if isTapDance { return .tapDance }
        if tap != nil && hold != nil { return nil }
        guard let only = tap ?? hold else { return .transparent }
        if only.isTransparent { return .transparent }
        return only.isNone ? .disabled : nil
    }

    /// A tap dance: a double tap or tap-then-hold makes the generator build the key as one (spec §6.5).
    var isTapDance: Bool { doubleTap != nil || tapHold != nil }

    /// True when QMK writes a tap and hold as one keycode, `MT()`, `LT()` or a `*_T()`, which every key with the pair
    /// shares: a plain basic tap and a single-modifier, mod-tap function (`MEH_T`) or momentary-layer (0–15) hold. Any other dual-function
    /// key the generator numbers per key. The generator builds the keycode exactly when this holds.
    public static func isModTapOrLayerTap(tap: KeyAction, hold: KeyAction) -> Bool {
        guard tap.modifiers.isEmpty, tap.macro == nil, KeycodeCatalog.isBasic(tap.code), hold.macro == nil, hold.modifiers.isEmpty
        else { return false }
        if KeycodeCatalog.modTapFunctions.contains(hold.code) { return true }
        if let m = KeycodeCatalog.modifier(forCode: hold.code), m.rawValue.nonzeroBitCount == 1 { return true }
        return hold.canonicalCode == "MO" && hold.layer.map((0...15).contains) == true
    }
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
