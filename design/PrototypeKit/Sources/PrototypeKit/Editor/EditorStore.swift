import Foundation
import Observation

/// What is selected in the editor.
public struct EditorSelection: Hashable, Sendable {
    /// Layer being shown/edited.
    public var layer: Int
    /// Selected key index, or nil for no key.
    public var keyIndex: Int?
    /// Slot the inspector edits.
    public var slot: KeySlot

    public init(layer: Int = 0, keyIndex: Int? = nil, slot: KeySlot = .tap) {
        self.layer = layer
        self.keyIndex = keyIndex
        self.slot = slot
    }
}

/// The document + editor state for a layout. All mutations go through undoable operations.
///
/// Each edit snapshots the whole layout and selection (cheap: a layout is a few kB of value types) and
/// registers the inverse with ``undoManager`` under a readable action name ("Set Tap", "Rename Layer").
/// Attach the store's manager to the window so ⌘Z / ⇧⌘Z work:
/// ```swift
/// .environment(\.undoManager, store.undoManager)   // or pass the window's manager into init
/// ```
@MainActor
@Observable
public final class EditorStore {
    /// The document.
    public private(set) var layout: KeyboardLayout
    public var selection: EditorSelection
    /// Undo stack (shared with the window if you pass one in).
    @ObservationIgnored public let undoManager: UndoManager
    public let geometry: BoardGeometry
    /// True after any edit since init or ``markSaved()``.
    public private(set) var hasUnsavedChanges = false
    /// Bumped on every change, including undo/redo (lets views refresh `canUndo`).
    public private(set) var changeCount = 0

    public init(layout: KeyboardLayout = Samples.layout, geometry: BoardGeometry = .voyager, undoManager: UndoManager = UndoManager()) {
        self.layout = layout
        self.geometry = geometry
        self.undoManager = undoManager
        self.selection = EditorSelection()
    }

    // MARK: Read helpers

    public var currentLayer: Layer? { layout.layers.indices.contains(selection.layer) ? layout.layers[selection.layer] : nil }

    /// The selected key as stored (may be transparent).
    public var selectedKey: Key? { selection.keyIndex.flatMap { layout.key(layer: selection.layer, index: $0) } }

    /// The selected action in the selected slot.
    public var selectedAction: KeyAction? { selectedKey?[selection.slot] }

    /// Resolved legend for any key on the current layer.
    public func legend(at index: Int) -> ResolvedLegend { Legends.legend(layout: layout, layer: selection.layer, index: index) }

    public var canUndo: Bool { _ = changeCount; return undoManager.canUndo }
    public var canRedo: Bool { _ = changeCount; return undoManager.canRedo }
    public var undoActionName: String { _ = changeCount; return undoManager.undoActionName }
    public var redoActionName: String { _ = changeCount; return undoManager.redoActionName }

    public func undo() { undoManager.undo() }
    public func redo() { undoManager.redo() }

    /// Clears ``hasUnsavedChanges``.
    public func markSaved() { hasUnsavedChanges = false }

    // MARK: Selection

    public func select(layer: Int) {
        guard layout.layers.indices.contains(layer) else { return }
        selection.layer = layer
    }

    public func select(key index: Int?, slot: KeySlot? = nil) {
        selection.keyIndex = index.flatMap { (0..<layout.keyCount).contains($0) ? $0 : nil }
        if let slot { selection.slot = slot }
    }

    /// Arrow-key navigation across the board (crosses halves, reaches thumbs). Selects key 0 if nothing is selected.
    public func moveSelection(_ direction: BoardGeometry.Direction) {
        guard let i = selection.keyIndex else { selection.keyIndex = 0; return }
        if let n = geometry.neighbor(of: i, toward: direction) { selection.keyIndex = n }
    }

    // MARK: Key edits

    /// Sets (or clears, with nil) the action in a slot. Defaults to the current selection.
    public func setAction(_ action: KeyAction?, slot: KeySlot? = nil, layer: Int? = nil, index: Int? = nil) {
        guard let (l, i) = target(layer, index) else { return }
        let s = slot ?? selection.slot
        edit(action == nil ? "Clear \(s.title)" : "Set \(s.title)") { $0.updateKey(layer: l, index: i) { $0[s] = action } }
    }

    /// Sets a slot to a plain keycode, keeping the slot's existing modifiers unless `modifiers` is given.
    public func setCode(_ code: String, modifiers: Modifiers? = nil, slot: KeySlot? = nil, layer: Int? = nil, index: Int? = nil) {
        guard let (l, i) = target(layer, index) else { return }
        let s = slot ?? selection.slot
        let existing = layout.key(layer: l, index: i)?[s]
        let action = KeyAction(code: code, layer: nil, modifiers: modifiers ?? existing?.modifiers ?? [], color: existing?.color)
        setAction(action, slot: s, layer: l, index: i)
    }

    /// Sets the tap action's keycode (convenience).
    public func setTap(_ code: String, modifiers: Modifiers = [], layer: Int? = nil, index: Int? = nil) {
        setAction(KeyAction(code: code, modifiers: modifiers), slot: .tap, layer: layer, index: index)
    }

    /// Sets the hold action's keycode (convenience). Use ``setHoldLayer(_:layer:index:)`` for layer holds.
    public func setHold(_ code: String, modifiers: Modifiers = [], layer: Int? = nil, index: Int? = nil) {
        setAction(KeyAction(code: code, modifiers: modifiers), slot: .hold, layer: layer, index: index)
    }

    /// Makes the hold slot activate a layer while held (`MO`), turning tap+hold keys into layer-tap keys.
    public func setHoldLayer(_ target: Int, layer: Int? = nil, index: Int? = nil) {
        setAction(.momentary(target), slot: .hold, layer: layer, index: index)
    }

    /// Sets modifiers on the action in a slot.
    public func setModifiers(_ modifiers: Modifiers, slot: KeySlot? = nil, layer: Int? = nil, index: Int? = nil) {
        guard let (l, i) = target(layer, index) else { return }
        let s = slot ?? selection.slot
        edit("Change Modifiers") { $0.updateKey(layer: l, index: i) { $0[s]?.modifiers = modifiers } }
    }

    /// Sets or clears the custom label (trimmed; empty clears).
    public func setLabel(_ label: String?, layer: Int? = nil, index: Int? = nil) {
        guard let (l, i) = target(layer, index) else { return }
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (trimmed?.isEmpty ?? true) ? nil : trimmed
        edit(value == nil ? "Clear Label" : "Set Label") { $0.updateKey(layer: l, index: i) { $0.customLabel = value } }
    }

    /// Sets or clears a key's LED colour on its layer.
    public func setColor(_ color: HexColor?, layer: Int? = nil, index: Int? = nil) {
        guard let (l, i) = target(layer, index) else { return }
        edit(color == nil ? "Clear Key Colour" : "Set Key Colour") { $0.updateKey(layer: l, index: i) { $0.glowColor = color } }
    }

    /// Paints several keys at once (one undo step).
    public func paint(_ color: HexColor?, keys indices: [Int], layer: Int? = nil) {
        let l = layer ?? selection.layer
        edit("Paint Keys") { doc in for i in indices { doc.updateKey(layer: l, index: i) { $0.glowColor = color } } }
    }

    /// Makes a key transparent.
    public func makeTransparent(layer: Int? = nil, index: Int? = nil) {
        guard let (l, i) = target(layer, index) else { return }
        edit("Make Transparent") { $0.updateKey(layer: l, index: i) { $0 = .transparent } }
    }

    /// Disables a key (`KC_NO`).
    public func disable(layer: Int? = nil, index: Int? = nil) {
        guard let (l, i) = target(layer, index) else { return }
        edit("Disable Key") { $0.updateKey(layer: l, index: i) { $0 = .none } }
    }

    /// Replaces a whole key.
    public func setKey(_ key: Key, layer: Int? = nil, index: Int? = nil, actionName: String = "Edit Key") {
        guard let (l, i) = target(layer, index) else { return }
        edit(actionName) { $0.updateKey(layer: l, index: i) { $0 = key } }
    }

    /// Swaps two keys on a layer.
    public func swapKeys(_ a: Int, _ b: Int, layer: Int? = nil) {
        let l = layer ?? selection.layer
        guard let ka = layout.key(layer: l, index: a), let kb = layout.key(layer: l, index: b) else { return }
        edit("Swap Keys") { doc in
            doc.updateKey(layer: l, index: a) { $0 = kb }
            doc.updateKey(layer: l, index: b) { $0 = ka }
        }
    }

    // MARK: Layer edits

    /// Adds an all-transparent layer at the end and selects it. Returns its index.
    @discardableResult
    public func addLayer(title: String = "New Layer", color: HexColor? = nil) -> Int {
        let newIndex = layout.layers.count
        edit("Add Layer") { $0.layers.append(.transparent(title: title, color: color, keyCount: $0.keyCount)) }
        selection.layer = newIndex
        return newIndex
    }

    /// Duplicates a layer right after itself.
    @discardableResult
    public func duplicateLayer(_ index: Int) -> Int? {
        guard layout.layers.indices.contains(index) else { return nil }
        edit("Duplicate Layer") { doc in
            var copy = doc.layers[index]
            copy.id = UUID().uuidString
            copy.title += " Copy"
            doc.layers.append(copy)
            doc.moveLayer(from: doc.layers.count - 1, to: index + 1)
        }
        selection.layer = index + 1
        return index + 1
    }

    public func renameLayer(_ index: Int, to title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard layout.layers.indices.contains(index), !t.isEmpty else { return }
        edit("Rename Layer") { $0.layers[index].title = t }
    }

    public func setLayerColor(_ color: HexColor?, layer index: Int) {
        guard layout.layers.indices.contains(index) else { return }
        edit("Change Layer Colour") { $0.layers[index].color = color }
    }

    /// Reorders a layer; MO/TG/TO/… references follow it. Selection follows the moved layer.
    public func moveLayer(from source: Int, to destination: Int) {
        guard layout.layers.indices.contains(source), layout.layers.indices.contains(destination), source != destination else { return }
        let selectedID = currentLayer?.id
        edit("Move Layer") { $0.moveLayer(from: source, to: destination) }
        if let id = selectedID, let i = layout.layers.firstIndex(where: { $0.id == id }) { selection.layer = i }
    }

    /// Deletes a layer (not the last remaining one). Keys that pointed at it become `KC_NO`.
    public func deleteLayer(_ index: Int) {
        guard layout.layers.count > 1, layout.layers.indices.contains(index) else { return }
        edit("Delete Layer") { $0.removeLayer(at: index) }
        selection.layer = min(selection.layer, layout.layers.count - 1)
    }

    // MARK: Document edits

    public func setTitle(_ title: String) { edit("Rename Layout") { $0.title = title } }

    public func setSetting(_ id: String, to value: SettingValue?, catalog: SettingsCatalog = .voyager) {
        edit("Change Setting") { doc in
            // Oryx stores config sparsely: a value equal to the default is removed.
            if let value, value != catalog.setting(id: id)?.defaultValue { doc.settings[id] = value } else { doc.settings[id] = nil }
        }
    }

    public func setCombos(_ combos: [Combo]) { edit("Edit Combos") { $0.combos = combos } }

    /// Replaces the whole document (e.g. after import), undoably.
    public func replaceLayout(_ newLayout: KeyboardLayout, actionName: String = "Replace Layout") {
        edit(actionName) { $0 = newLayout }
        selection = EditorSelection(layer: min(selection.layer, newLayout.layers.count - 1))
    }

    // MARK: Undo plumbing

    private func target(_ layer: Int?, _ index: Int?) -> (Int, Int)? {
        let l = layer ?? selection.layer
        guard let i = index ?? selection.keyIndex, layout.key(layer: l, index: i) != nil else { return nil }
        return (l, i)
    }

    private struct Snapshot { var layout: KeyboardLayout; var selection: EditorSelection }

    private func edit(_ name: String, _ mutate: (inout KeyboardLayout) -> Void) {
        let before = Snapshot(layout: layout, selection: selection)
        var next = layout
        mutate(&next)
        guard next != layout else { return }
        layout = next
        hasUnsavedChanges = true
        changeCount += 1
        registerUndo(restoring: before, name: name)
    }

    private func registerUndo(restoring snapshot: Snapshot, name: String) {
        let current = Snapshot(layout: layout, selection: selection)
        undoManager.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated {
                store.layout = snapshot.layout
                store.selection = snapshot.selection
                store.hasUnsavedChanges = true
                store.changeCount += 1
                store.registerUndo(restoring: current, name: name)
            }
        }
        undoManager.setActionName(name)
    }
}
