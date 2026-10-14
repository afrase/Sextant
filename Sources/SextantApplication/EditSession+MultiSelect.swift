import Foundation
import SextantDomain

/// Edits across several keys and layers (ADR 0047): the picker's selection-wide assignments, Copy To Layer, the keys
/// pasteboard, and Copy Layer To. The single-key edits in EditSession.swift already act on every selected key.
extension EditSession {
    // MARK: Selecting

    /// The keys selected on the shown board, ascending: every selected key while the window shows several
    /// (``showsSeveralKeys``), else the anchor alone. Edits without an index act on these.
    public var selectedKeys: [Int] {
        guard showsSeveralKeys() else { return selection.keyIndex.map { [$0] } ?? [] }
        return selection.keyIndices
    }

    /// Selects several keys (spec §5.4), `anchor` as the anchor, else the first; keys off the board are left out.
    /// `slot`, when given, becomes the selected slot.
    public func select(keys indices: [Int], anchor: Int? = nil, slot: KeySlot? = nil) {
        let keys = indices.filter((0..<layout.keyCount).contains)
        selection.select(keys: keys, anchor: anchor.flatMap { keys.contains($0) ? $0 : nil } ?? keys.first)
        if let slot { selection.slot = slot }
    }

    /// ⌘-click: adds the key to the selection, or takes it out. The anchor taken out passes to the lowest other key.
    public func toggle(key index: Int) {
        guard (0..<layout.keyCount).contains(index) else { return }
        var keys = selectedKeys
        if let at = keys.firstIndex(of: index) {
            keys.remove(at: at)
            selection.select(keys: keys, anchor: selection.keyIndex == index ? keys.first : selection.keyIndex)
        } else {
            selection.select(keys: keys + [index], anchor: selection.keyIndex ?? index)
        }
    }

    /// ⇧-click: the keys from the anchor to `index` in the board's reading order, keeping the anchor; with no anchor,
    /// that key alone.
    public func selectRange(to index: Int) {
        guard let anchor = selection.keyIndex else { return select(keys: [index]) }
        select(keys: geometry.range(from: anchor, to: index), anchor: anchor)
    }

    /// Sets a slot of each selected key to what `make` returns for the action there, so the picker keeps each key's own
    /// chord.
    public func setAction(slot: KeySlot? = nil, _ make: (KeyAction?) -> KeyAction?) {
        let keys = targets()
        guard !keys.isEmpty else { return }
        let s = slot ?? selection.slot
        edit(Self.slotEditName(s, clearing: false, count: keys.count)) { doc in
            for (l, i) in keys { doc.updateKey(layer: l, index: i) { $0[s] = make($0[s]) } }
        }
    }

    /// Puts a macro on the tap of every selected key (the picker's Macros row), as ``assignMacro(_:layer:index:)`` puts it
    /// on one: a draft moves onto the first key and the others get copies. Selects the macro on the anchor.
    public func assignMacroToSelectedKeys(_ locator: MacroLocator) {
        let keys = targets()
        guard keys.count > 1 else {
            if let key = keys.first { assignMacro(locator, layer: key.layer, index: key.index) }
            return
        }
        let anchor = selection.keyIndex
        var placed: [Int: MacroLocator] = [:]
        edit(
            String(localized: "Assign Macro to \(keys.count) Keys"),
            select: { selection in
                selection.macro = anchor.flatMap { placed[$0] }
                selection.step = nil
            }
        ) { doc in
            var source = locator
            for (l, i) in keys {
                guard let at = doc.assignMacro(at: source, layer: l, index: i) else { continue }
                placed[i] = at
                source = at
            }
        }
    }

    // MARK: Keys between layers and the pasteboard

    /// Copies the selected keys of the shown layer to the same places on another layer (spec §5.4 "Copy To Layer").
    public func copyKeys(toLayer target: Int) {
        let keys = targets()
        guard target != selection.layer, layout.layers.indices.contains(target), !keys.isEmpty else { return }
        let title = layout.layers[target].title
        let name =
            keys.count == 1 ? String(localized: "Copy Key to \(title)") : String(localized: "Copy \(keys.count) Keys to \(title)")
        edit(name) { doc in
            for (l, i) in keys {
                guard let key = doc.key(layer: l, index: i) else { continue }
                doc.updateKey(layer: target, index: i) { $0 = key }
            }
        }
    }

    /// The selected keys of the shown layer, as stored, for ⌘C; nil with none selected.
    public var copiedKeys: CopiedKeys? { CopiedKeys(layout: layout, layer: selection.layer, indices: selectedKeys) }

    /// ⌘X: returns the selected keys and makes them transparent, as one undo step ("Cut 3 Keys").
    public func cutKeys() -> CopiedKeys? {
        guard let copied = copiedKeys else { return nil }
        let keys = targets()
        let name = keys.count == 1 ? String(localized: "Cut Key") : String(localized: "Cut \(keys.count) Keys")
        edit(name) { doc in
            for (l, i) in keys { doc.updateKey(layer: l, index: i) { $0 = .transparent } }
        }
        return copied
    }

    /// ⌘V on the shown layer, as one undo step; it needs a selected key. One copied key goes onto every selected key
    /// ("Paste Key"); several go back to their own places, which needs the same board, and are selected, even when they
    /// were there already. A layer action whose layer this layout lacks pastes as `KC_NO`. False when nothing could be
    /// pasted.
    @discardableResult
    public func pasteKeys(_ copied: CopiedKeys) -> Bool {
        let entries = copied.entries(forLayerCount: layout.layers.count)
        let keys = targets()
        guard !keys.isEmpty else { return false }
        if entries.count == 1, let key = entries.first?.key {
            let name = keys.count == 1 ? String(localized: "Paste Key") : String(localized: "Paste onto \(keys.count) Keys")
            edit(name) { doc in
                for (l, i) in keys { doc.updateKey(layer: l, index: i) { $0 = key } }
            }
            return true
        }
        let l = selection.layer
        guard copied.fitsPositions(of: layout), layout.layers.indices.contains(l), !entries.isEmpty else { return false }
        let indices = entries.map(\.index)
        let name = entries.count == 1 ? String(localized: "Paste Key") : String(localized: "Paste \(entries.count) Keys")
        // Selected in `edit` too, so redo selects them again; undo keeps the selection from before, as for any edit.
        edit(name, select: { $0.select(keys: indices, anchor: indices.first) }) { doc in
            for entry in entries { doc.updateKey(layer: l, index: entry.index) { $0 = entry.key } }
        }
        // And outside `edit`, which stops at an edit that changes nothing: the keys show where the paste went either way.
        select(keys: indices, anchor: indices.first)
        return true
    }

    // MARK: Copy Layer To

    /// Copy Layer To (spec §6.1): replaces a layer's keys with another's, keeping its id, title and colour, and shows it.
    /// Layer keys keep their layer numbers, which mean the same layers within one layout.
    public func copyLayer(_ source: Int, to target: Int) {
        guard source != target, layout.layers.indices.contains(source), layout.layers.indices.contains(target) else { return }
        let title = layout.layers[target].title
        edit(String(localized: "Copy Layer to \(title)"), select: { $0.layer = target }) { doc in
            doc.layers[target].keys = doc.layers[source].keys
        }
    }

    /// Copy Layer To ▸ New Layer: a copy of a layer at the end ("Sym+Num Copy"), shown. Returns its index.
    @discardableResult
    public func appendLayer(copying source: Int) -> Int? {
        guard layout.layers.indices.contains(source) else { return nil }
        let newIndex = layout.layers.count
        edit(String(localized: "Copy Layer to New Layer"), select: { $0.layer = newIndex }) { doc in
            var copy = doc.layers[source]
            (copy.id, copy.oryxID, copy.oryxPreviousID) = (UUID().uuidString, nil, nil)
            copy.title = String(localized: "\(copy.title) Copy")
            doc.layers.append(copy)
        }
        return newIndex
    }
}
