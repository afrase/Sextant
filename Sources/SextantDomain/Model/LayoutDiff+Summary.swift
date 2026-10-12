import Foundation

/// Everything Sextant edits that differs between two layouts: the key and layer diff, plus the title, layer order,
/// settings, combos and Navigator, so an edit never reads as "no changes" (History, Save Revision's message; ADR 0043).
/// Oryx's swatches and revision info aren't counted: only an import changes them.
public struct LayoutChanges: Hashable, Sendable {
    /// Keys and layers. Each own key on a layer the old layout lacks is added, so a new layer's keys show on the board.
    public var diff: LayoutDiff
    /// Ids of the settings whose stored value differs, Navigator options included, sorted.
    public var settings: [String]
    /// Combos only one side has, compared by content: Oryx numbers combo ids by position, so ids aren't identities.
    public var addedCombos: [Combo]
    public var removedCombos: [Combo]
    /// The Navigator was attached, removed, changed kind or moved, or its automouse layer changed.
    public var navigatorChanged: Bool
    /// The layout was renamed.
    public var titleChanged: Bool
    /// Layers both sides have are in another order (the diff matches them by id, so a move alone has no key changes).
    public var layersMoved: Bool

    public var isEmpty: Bool {
        diff.isEmpty && settings.isEmpty && addedCombos.isEmpty && removedCombos.isEmpty && !navigatorChanged && !titleChanged
            && !layersMoved
    }

    /// How many things changed: each key, layer, setting and combo, the Navigator, the title and the layer order.
    public var count: Int {
        diff.keyChanges.count + diff.addedLayers.count + diff.removedLayers.count + diff.renamedLayers.count
            + diff.recoloredLayers.count + settings.count + addedCombos.count + removedCombos.count
            + [navigatorChanged, titleChanged, layersMoved].filter { $0 }.count
    }
}

extension KeyboardLayout {
    /// What changed from `old` to `self`, layers matched by id (``diff(from:)``).
    public func changes(from old: KeyboardLayout) -> LayoutChanges {
        var diff = diff(from: old)
        for layer in diff.addedLayers {
            guard let li = layers.firstIndex(where: { $0.id == layer.id }) else { continue }
            for (ki, key) in layer.keys.enumerated() where !key.isTransparent {
                diff.keyChanges.append(
                    KeyChange(
                        layer: li, layerID: layer.id, index: ki, before: nil, after: key, kind: .added,
                        changedSlots: KeySlot.allCases.filter { key[$0] != nil }, labelChanged: key.customLabel != nil,
                        colorChanged: key.glowColor != nil || key.tap?.color != nil))
            }
        }
        func differing(_ a: [String: SettingValue], _ b: [String: SettingValue]) -> Set<String> {
            Set(a.keys).union(b.keys).filter { a[$0] != b[$0] }
        }
        func content(_ combo: Combo) -> Combo {
            var combo = combo
            combo.id = ""
            return combo
        }
        let now = combos.map(content), was = old.combos.map(content)
        let shared = Set(layers.map(\.id)).intersection(old.layers.map(\.id))
        return LayoutChanges(
            diff: diff,
            settings: differing(settings, old.settings).union(differing(navigator?.options ?? [:], old.navigator?.options ?? [:])).sorted(),
            addedCombos: combos.filter { !was.contains(content($0)) },
            removedCombos: old.combos.filter { !now.contains(content($0)) },
            navigatorChanged: navigator?.kind != old.navigator?.kind || navigator?.side != old.navigator?.side
                || automouseLayer != old.automouseLayer,
            titleChanged: title != old.title,
            layersMoved: layers.map(\.id).filter(shared.contains) != old.layers.map(\.id).filter(shared.contains))
    }
}
