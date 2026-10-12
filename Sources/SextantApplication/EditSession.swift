import Foundation
import Observation
import SextantDomain
import os

/// What is selected in the editor. Undo restores it with the layout.
public struct EditorSelection: Hashable, Sendable {
    /// Layer being shown and edited.
    public var layer: Int
    /// Selected key index, or nil for no key.
    public var keyIndex: Int?
    /// Slot the inspector edits.
    public var slot: KeySlot
    /// Selected combo's id (the Combos page).
    public var combo: String?
    /// Selected macro and its selected step (the Macros page).
    public var macro: MacroLocator?
    public var step: Int?

    public init(layer: Int = 0, keyIndex: Int? = nil, slot: KeySlot = .tap) {
        self.layer = layer
        self.keyIndex = keyIndex
        self.slot = slot
    }
}

/// One open layout: the document, the selection, every undoable edit, and autosave.
///
/// Each edit snapshots the layout and selection (a layout is a few kB of values) and registers the
/// inverse on ``undoManager`` under a readable action name ("Set Tap", "Rename Layer"). Set the window's
/// manager so ⌘Z and the Edit menu work through the responder chain. Edits are written to the library
/// ``autosaveDelay`` after the last change (spec §2.3), and to a recovery copy at once, so a crash or a failing
/// save loses nothing (``Library/open(_:autosaveDelay:)`` restores it).
@MainActor
@Observable
public final class EditSession {
    public let id: UUID
    /// The document.
    public private(set) var layout: KeyboardLayout
    public var selection = EditorSelection()
    /// Revisions, oldest first. Internal setter, like `revisionBaseline` and `library`: History's edits live in
    /// `EditSession+History.swift` (docs/v1-plan.md, rule 6).
    public internal(set) var revisions: [RevisionSummary]
    public private(set) var origin: LayoutOrigin
    /// The board's key shapes, with the Navigator disc on the layout's Navigator side.
    public private(set) var geometry: BoardGeometry
    /// Bumped on every change, including undo and redo, so views refresh `canUndo`.
    public private(set) var changeCount = 0
    /// The last autosave failure, if any (cleared by the next successful save).
    public private(set) var saveError: LibraryError?
    /// The document was restored from a recovery copy: edits that hadn't reached the library before Sextant quit.
    /// The window clears it when its notice is dismissed.
    public var recoveredUnsavedChanges = false
    /// The layout as of the last revision, for "Edited" in the window subtitle (spec §3.4). Nil when the stored
    /// working copy already differed from its last revision at open: edited until the next revision.
    var revisionBaseline: KeyboardLayout?

    /// The window's undo manager. Edits made while it is nil are not undoable.
    @ObservationIgnored public weak var undoManager: UndoManager?
    @ObservationIgnored let library: any LayoutLibrary
    @ObservationIgnored private let autosaveDelay: Duration
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    /// Recovery writes run in order; each waits for the one before.
    @ObservationIgnored private var recoveryWrite: Task<Void, Never>?
    @ObservationIgnored private var recoveryGeneration = 0
    @ObservationIgnored private let log = Logger(subsystem: "com.sextant.app", category: "application")

    public init(stored: StoredLayout, library: any LayoutLibrary, autosaveDelay: Duration = .seconds(1)) {
        id = stored.entry.id
        layout = stored.layout
        revisionBaseline = stored.hasEditsSinceLastRevision ? nil : stored.layout
        revisions = stored.revisions
        origin = stored.entry.origin
        self.library = library
        geometry = Self.geometry(of: stored.layout)
        self.autosaveDelay = autosaveDelay
    }

    /// The board a layout shows: its Navigator's side moves the keys. Exports draw the same board as the window.
    public static func geometry(of layout: KeyboardLayout) -> BoardGeometry {
        (layout.board ?? .voyager).geometry(navigator: layout.navigator.map { $0.side == .left ? .left : .right })
    }

    // MARK: Read helpers

    public var currentLayer: Layer? { layout.layers.indices.contains(selection.layer) ? layout.layers[selection.layer] : nil }

    /// The selected key as stored (may be transparent).
    public var selectedKey: Key? { selection.keyIndex.flatMap { layout.key(layer: selection.layer, index: $0) } }

    /// The selected action in the selected slot.
    public var selectedAction: KeyAction? { selectedKey?[selection.slot] }

    /// Resolved legend for a key on the current layer.
    public func legend(at index: Int) -> ResolvedLegend { Legends.legend(layout: layout, layer: selection.layer, index: index) }

    /// True when the layout differs from the last revision (undoing back to it clears this).
    public var isEditedSinceRevision: Bool { revisionBaseline.map { layout != $0 } ?? true }

    public var canUndo: Bool {
        _ = changeCount
        return undoManager?.canUndo ?? false
    }
    public var canRedo: Bool {
        _ = changeCount
        return undoManager?.canRedo ?? false
    }

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
        guard let i = selection.keyIndex else {
            selection.keyIndex = 0
            return
        }
        if let n = geometry.neighbor(of: i, toward: direction) { selection.keyIndex = n }
    }

    // MARK: Key edits

    /// Sets (or clears, with nil) the action in a slot. Defaults to the current selection.
    public func setAction(_ action: KeyAction?, slot: KeySlot? = nil, layer: Int? = nil, index: Int? = nil) {
        guard let (l, i) = target(layer, index) else { return }
        let s = slot ?? selection.slot
        let name = action == nil ? String(localized: "Clear \(s.title)") : String(localized: "Set \(s.title)")
        edit(name) { $0.updateKey(layer: l, index: i) { $0[s] = action } }
    }

    /// Sets a slot to a plain keycode, keeping the slot's existing modifiers unless `modifiers` is given.
    public func setCode(_ code: String, modifiers: Modifiers? = nil, slot: KeySlot? = nil, layer: Int? = nil, index: Int? = nil) {
        guard let (l, i) = target(layer, index) else { return }
        let s = slot ?? selection.slot
        let existing = layout.key(layer: l, index: i)?[s]
        let action = KeyAction(code: code, layer: nil, modifiers: modifiers ?? existing?.modifiers ?? [], color: existing?.color)
        setAction(action, slot: s, layer: l, index: i)
    }

    /// Makes the hold slot activate a layer while held (`MO`), turning tap+hold keys into layer-tap keys.
    public func setHoldLayer(_ target: Int, layer: Int? = nil, index: Int? = nil) {
        setAction(.momentary(target), slot: .hold, layer: layer, index: index)
    }

    /// Sets modifiers on the action in a slot.
    public func setModifiers(_ modifiers: Modifiers, slot: KeySlot? = nil, layer: Int? = nil, index: Int? = nil) {
        guard let (l, i) = target(layer, index) else { return }
        let s = slot ?? selection.slot
        edit(String(localized: "Change Modifiers")) { $0.updateKey(layer: l, index: i) { $0[s]?.modifiers = modifiers } }
    }

    /// Sets or clears the custom label (trimmed; empty clears).
    public func setLabel(_ label: String?, layer: Int? = nil, index: Int? = nil) {
        guard let (l, i) = target(layer, index) else { return }
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (trimmed?.isEmpty ?? true) ? nil : trimmed
        edit(value == nil ? String(localized: "Clear Label") : String(localized: "Set Label")) {
            $0.updateKey(layer: l, index: i) { $0.customLabel = value }
        }
    }

    /// Sets or clears a key's LED colour on its layer.
    public func setColor(_ color: HexColor?, layer: Int? = nil, index: Int? = nil) {
        guard let (l, i) = target(layer, index) else { return }
        edit(color == nil ? String(localized: "Clear Key Color") : String(localized: "Set Key Color")) {
            $0.updateKey(layer: l, index: i) { $0.glowColor = color }
        }
    }

    /// Paints several keys at once (one undo step, e.g. "Paint 6 Keys").
    public func paint(_ color: HexColor?, keys indices: [Int], layer: Int? = nil) {
        let l = layer ?? selection.layer
        edit(String(localized: "Paint \(indices.count) Keys")) { doc in
            for i in indices { doc.updateKey(layer: l, index: i) { $0.glowColor = color } }
        }
    }

    /// Makes a key transparent.
    public func makeTransparent(layer: Int? = nil, index: Int? = nil) {
        guard let (l, i) = target(layer, index) else { return }
        edit(String(localized: "Make Transparent")) { $0.updateKey(layer: l, index: i) { $0 = .transparent } }
    }

    /// Disables a key (`KC_NO`).
    public func disable(layer: Int? = nil, index: Int? = nil) {
        guard let (l, i) = target(layer, index) else { return }
        edit(String(localized: "Disable Key")) { $0.updateKey(layer: l, index: i) { $0 = .none } }
    }

    /// Copies the inherited definition of a transparent key onto its own layer (spec §5.1 "Override Key").
    public func overrideInherited(layer: Int? = nil, index: Int? = nil) {
        guard let (l, i) = target(layer, index) else { return }
        let resolved = layout.resolvedKey(layer: l, index: i)
        guard resolved.isInherited else { return }
        edit(String(localized: "Override Key")) { $0.updateKey(layer: l, index: i) { $0 = resolved.effective } }
    }

    /// Replaces a whole key.
    public func setKey(_ key: Key, layer: Int? = nil, index: Int? = nil, actionName: String = String(localized: "Edit Key")) {
        guard let (l, i) = target(layer, index) else { return }
        edit(actionName) { $0.updateKey(layer: l, index: i) { $0 = key } }
    }

    /// Swaps two keys on a layer; with `copy`, puts a copy of the first onto the second instead (⌥-drag).
    public func swapKeys(_ a: Int, _ b: Int, layer: Int? = nil, copy: Bool = false) {
        let l = layer ?? selection.layer
        guard a != b, let ka = layout.key(layer: l, index: a), let kb = layout.key(layer: l, index: b) else { return }
        edit(copy ? String(localized: "Copy Key") : String(localized: "Swap Keys")) { doc in
            doc.updateKey(layer: l, index: b) { $0 = ka }
            if !copy { doc.updateKey(layer: l, index: a) { $0 = kb } }
        }
    }

    // MARK: Layer edits

    /// Adds an all-transparent layer at the end and selects it. Returns its index.
    @discardableResult
    public func addLayer(title: String? = nil, color: HexColor? = nil) -> Int {
        let newIndex = layout.layers.count
        let name = title ?? String(localized: "Layer \(newIndex)")
        edit(String(localized: "New Layer"), select: { $0.layer = newIndex }) {
            $0.layers.append(.transparent(title: name, color: color, keyCount: $0.keyCount))
        }
        return newIndex
    }

    /// Duplicates a layer right after itself ("Sym+Num Copy").
    @discardableResult
    public func duplicateLayer(_ index: Int) -> Int? {
        guard layout.layers.indices.contains(index) else { return nil }
        edit(String(localized: "Duplicate Layer"), select: { $0.layer = index + 1 }) { doc in
            var copy = doc.layers[index]
            copy.id = UUID().uuidString
            copy.title = String(localized: "\(copy.title) Copy")
            doc.layers.append(copy)
            doc.moveLayer(from: doc.layers.count - 1, to: index + 1)
        }
        return index + 1
    }

    public func renameLayer(_ index: Int, to title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard layout.layers.indices.contains(index), !t.isEmpty else { return }
        edit(String(localized: "Rename Layer")) { $0.layers[index].title = t }
    }

    public func setLayerColor(_ color: HexColor?, layer index: Int) {
        guard layout.layers.indices.contains(index) else { return }
        edit(String(localized: "Set Layer Color")) { $0.layers[index].color = color }
    }

    /// Reorders a layer; MO/TG/TO/… references follow it, and so does the selection.
    public func moveLayer(from source: Int, to destination: Int) {
        guard layout.layers.indices.contains(source), layout.layers.indices.contains(destination), source != destination else { return }
        let selectedID = currentLayer?.id
        edit(
            String(localized: "Move Layer"),
            select: { selection, doc in
                if let i = doc.layers.firstIndex(where: { $0.id == selectedID }) { selection.layer = i }
            }
        ) { $0.moveLayer(from: source, to: destination) }
    }

    /// Deletes a layer (not the last one). Keys that pointed at it become `KC_NO`.
    public func deleteLayer(_ index: Int) {
        guard layout.layers.count > 1, layout.layers.indices.contains(index) else { return }
        edit(
            String(localized: "Delete Layer"),
            select: { selection, doc in
                // Keep showing the same layer when one below it goes; clamp when the shown one goes.
                if index < selection.layer { selection.layer -= 1 }
                selection.layer = min(selection.layer, doc.layers.count - 1)
            }
        ) { $0.removeLayer(at: index) }
    }

    /// Makes every key on a layer transparent.
    public func clearLayer(_ index: Int) {
        guard layout.layers.indices.contains(index) else { return }
        edit(String(localized: "Clear Layer")) { doc in
            doc.layers[index].keys = Array(repeating: .transparent, count: doc.keyCount)
        }
    }

    // MARK: Document edits

    public func setTitle(_ title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        edit(String(localized: "Rename Layout")) { $0.title = t }
    }

    /// Sets a firmware setting, sparsely as Oryx stores config (``KeyboardLayout/store(_:for:)``): nil or the unset
    /// value removes it, and Navigator settings go to the Navigator's options. Ids outside the catalog are ignored.
    public func setSetting(_ id: String, to value: SettingValue?, catalog: SettingsCatalog = .voyager) {
        guard let setting = catalog.setting(id: id) else { return }
        edit(String(localized: "Change Setting")) { $0.store(value, for: setting) }
    }

    /// Attaches, changes or removes (nil) the Navigator (``KeyboardLayout/setNavigator(_:)``). The UI doesn't offer the
    /// knob: the generator can't build it.
    public func setNavigator(_ kind: NavigatorConfig.Kind?) {
        edit(String(localized: "Set Navigator")) { $0.setNavigator(kind) }
    }

    /// Moves the Navigator to the other half, keeping its options.
    public func moveNavigator(to side: NavigatorConfig.Side) {
        let name = side == .left ? String(localized: "Move Navigator to Left") : String(localized: "Move Navigator to Right")
        edit(name) { $0.navigator?.side = side }
    }

    // MARK: Import

    /// Records a layout imported from Oryx in History, then makes it the document as one undoable edit that keeps
    /// the title (spec §8.1). Edits since the last revision are checkpointed first; a failure leaves the document as
    /// it was.
    public func applyImport(_ imported: KeyboardLayout) async throws(LibraryError) {
        try await checkpoint(String(localized: "Before importing from Oryx"))
        var next = imported
        next.title = layout.title
        let draft = RevisionDraft(source: .import, message: imported.oryx?.message, layout: next)
        revisions.append(try await library.appendRevision(draft, to: id))
        revisionBaseline = next
        edit(
            String(localized: "Import from Oryx"),
            select: { selection, doc in
                selection.layer = min(selection.layer, max(doc.layers.count - 1, 0))
                // Oryx combo ids are positions, so the old id may now name another combo.
                selection.combo = nil
            }
        ) { $0 = next }
        await flush()
        // A temporary session (no window open) is discarded after this; its save error must not be.
        if let saveError { throw saveError }
    }

    // MARK: Saving

    /// Before an edit replaces the whole document (an import, a restore): writes pending edits, then records them as a
    /// revision when the working copy has moved past the last one.
    func checkpoint(_ message: String) async throws(LibraryError) {
        await flush()
        // Unsaved edits would be checkpointed from a stale copy: stop rather than replace them.
        if let saveError { throw saveError }
        if try await library.load(id).hasEditsSinceLastRevision { try await saveRevision(source: .save, message: message) }
    }

    /// Writes any pending change now (window close, quit, before a build, Try Again). A failed save is still pending.
    public func flush() async {
        if pendingSave != nil || saveError != nil {
            pendingSave?.cancel()
            pendingSave = nil
            await save()
        }
        await recoveryWrite?.value
    }

    /// Makes a recovery copy the document. It is saved like any edit; the window says what happened.
    func recover(_ recovered: KeyboardLayout) {
        layout = recovered
        recoveredUnsavedChanges = true
        changed()
    }

    /// Records the current layout as a revision (⌘S, every flash).
    @discardableResult
    public func saveRevision(source: RevisionSource, message: String?) async throws(LibraryError) -> RevisionSummary {
        await flush()
        let saved = layout
        let summary = try await library.appendRevision(RevisionDraft(source: source, message: message, layout: saved), to: id)
        revisions.append(summary)
        revisionBaseline = saved
        return summary
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let delay = autosaveDelay
        // Holds the session until the save lands, so a closed window still writes its last change.
        pendingSave = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self.save()
        }
    }

    private func save() async {
        let saved = layout
        do {
            try await library.save(saved, to: id)
            saveError = nil
            // The library has every change, unless one came in while this save ran.
            if saved == layout { queueRecovery(nil) }
        } catch {
            log.error("Autosave failed: \(String(describing: error), privacy: .public)")
            saveError = error
        }
    }

    // MARK: Undo plumbing
    // Internal, not private: features add their edits in `EditSession+<Feature>.swift` (docs/v1-plan.md, rule 6).

    /// The key an edit acts on: the given layer and index, else the selection's; nil when there is no such key.
    func target(_ layer: Int?, _ index: Int?) -> (Int, Int)? {
        let l = layer ?? selection.layer
        guard let i = index ?? selection.keyIndex, layout.key(layer: l, index: i) != nil else { return nil }
        return (l, i)
    }

    private struct Snapshot {
        var layout: KeyboardLayout
        var selection: EditorSelection
    }

    /// Applies an edit as one undo step. `select` adjusts the selection to the new layout before the redo
    /// snapshot is taken, so redo restores it too.
    func edit(
        _ name: String, select: (inout EditorSelection, KeyboardLayout) -> Void = { _, _ in },
        _ mutate: (inout KeyboardLayout) -> Void
    ) {
        let before = Snapshot(layout: layout, selection: selection)
        var next = layout
        mutate(&next)
        guard next != layout else { return }
        layout = next
        select(&selection, next)
        // An edit can remove the selected combo: Delete Layer takes the combos limited to that layer.
        if let combo = selection.combo, !next.combos.contains(where: { $0.id == combo }) { selection.combo = nil }
        // A selected key macro is a position: when Move Layer or Delete Layer shifts its layer, it follows by id, or goes.
        if case let .key(ref)? = selection.macro, selection.macro == before.selection.macro,
            before.layout.layers.indices.contains(ref.layer)
        {
            let id = before.layout.layers[ref.layer].id
            selection.macro = next.layers.firstIndex { $0.id == id }.map { .key(KeyRef(layer: $0, index: ref.index, slot: ref.slot)) }
        }
        changed()
        registerUndo(restoring: before, name: name)
    }

    func edit(_ name: String, select: (inout EditorSelection) -> Void, _ mutate: (inout KeyboardLayout) -> Void) {
        edit(name, select: { selection, _ in select(&selection) }, mutate)
    }

    private func changed() {
        changeCount += 1
        origin = origin.following(layout)
        // Only a Navigator change moves the disc; skipping equal values spares the board a redraw.
        let shapes = Self.geometry(of: layout)
        if shapes != geometry { geometry = shapes }
        recoveryGeneration += 1
        queueRecovery(layout)
        scheduleSave()
    }

    /// Writes `layout` to the recovery copy, or discards the copy when nil. Skipped when a newer change has queued its
    /// own write by the time this one's turn comes.
    private func queueRecovery(_ layout: KeyboardLayout?) {
        let generation = recoveryGeneration, previous = recoveryWrite
        recoveryWrite = Task {
            await previous?.value
            guard generation == self.recoveryGeneration else { return }
            guard let layout else { return await self.library.discardRecovery(of: self.id) }
            do {
                try await self.library.saveRecovery(layout, for: self.id)
            } catch {
                self.log.error("Recovery copy failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func registerUndo(restoring snapshot: Snapshot, name: String) {
        guard let undoManager else { return }
        let current = Snapshot(layout: layout, selection: selection)
        undoManager.registerUndo(withTarget: self) { session in
            MainActor.assumeIsolated {
                session.layout = snapshot.layout
                session.selection = snapshot.selection
                session.changed()
                session.registerUndo(restoring: current, name: name)
            }
        }
        undoManager.setActionName(name)
    }
}
