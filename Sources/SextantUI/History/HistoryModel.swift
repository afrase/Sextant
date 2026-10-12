import Foundation
import Observation
import SextantApplication
import SextantDomain

/// The History page of one open layout (spec §8.7, ADR 0043): the selected revision, what it is compared with, the
/// revisions' layouts once loaded, and the Save Revision sheet.
@MainActor
@Observable
final class HistoryModel {
    /// What the selected revision is compared with. Badges always describe the board's keys, the selected revision's,
    /// against it: compared with Current, "added" marks a key Current lacks, which Restore would bring back.
    enum Comparison: Hashable {
        case parent, current, onKeyboard
        case revision(String)
    }

    /// The selected revision and what changed against the comparison.
    struct Shown {
        var revision: RevisionSummary
        var layout: KeyboardLayout
        /// What the comparison names; nil when it names nothing (the first revision's parent, a keyboard that doesn't
        /// run this layout).
        var base: KeyboardLayout?
        var changes: LayoutChanges?
        /// Changed keys by layer and index of `layout`.
        var marks: [KeyRef: KeyChange]
    }

    let session: EditSession
    /// The revision the timeline selects; nil, or an id the layout lacks, selects the newest.
    var selectedID: String? {
        // A revision compared with itself has nothing to show.
        didSet { if case let .revision(id) = comparison, id == selected?.id { comparison = .parent } }
    }
    var comparison = Comparison.parent
    /// The Save Revision sheet's message while the sheet is up.
    var saveMessage: String?
    /// The id of a layer only the revision has, chosen in the strip; the page clears it when the selected layer changes.
    var pinnedLayer: String?
    /// The last failed load or restore, for the inspector.
    var error: LibraryError?
    /// A restore is running: a second one would append its revisions again.
    private(set) var isRestoring = false
    /// Revision layouts by id once loaded. Revisions never change, so they stay.
    private(set) var layouts: [String: KeyboardLayout] = [:]
    /// Each revision's change count against its parent, for the timeline.
    private(set) var counts: [String: Int] = [:]
    @ObservationIgnored private let onKeyboard: OnKeyboard?
    /// The board asks for every cap's mark, so the diff is worked out once per input.
    @ObservationIgnored private var memo: (key: MemoKey, shown: Shown?)?

    private struct MemoKey: Equatable {
        var revision: String
        var comparison: Comparison
        var loaded: Int
        var edits: Int
        var keyboard: String?
    }

    init(session: EditSession, onKeyboard: OnKeyboard?) {
        self.session = session
        self.onKeyboard = onKeyboard
    }

    // MARK: Revisions

    var selected: RevisionSummary? { session.revisions.last { $0.id == selectedID } ?? session.revisions.last }

    func parent(of revision: RevisionSummary) -> RevisionSummary? {
        guard let i = session.revisions.firstIndex(where: { $0.id == revision.id }), i > 0 else { return nil }
        return session.revisions[i - 1]
    }

    /// What the keyboard runs, when it runs this layout: a revision as flashed, never later edits (ADR 0039).
    var running: OnKeyboard.Running? { onKeyboard?.running.flatMap { $0.entry.id == session.id ? $0 : nil } }

    /// Loads the layouts not loaded yet, then the timeline's counts.
    func load() async {
        var loaded = layouts
        for revision in session.revisions where loaded[revision.id] == nil {
            do throws(LibraryError) {
                loaded[revision.id] = try await session.revisionLayout(revision.id)
            } catch {
                self.error = error
            }
        }
        guard loaded.count != layouts.count else { return }
        var counts: [String: Int] = [:]
        for (parent, revision) in zip(session.revisions, session.revisions.dropFirst()) {
            if let old = loaded[parent.id], let new = loaded[revision.id] { counts[revision.id] = new.changes(from: old).count }
        }
        layouts = loaded
        self.counts = counts
    }

    // MARK: Comparison

    func base(_ comparison: Comparison) -> KeyboardLayout? {
        switch comparison {
        case .parent: selected.flatMap(parent).flatMap { layouts[$0.id] }
        case .current: session.layout
        case .onKeyboard: running?.layout
        case let .revision(id): layouts[id]
        }
    }

    func canCompare(with comparison: Comparison) -> Bool {
        switch comparison {
        case .parent: selected.flatMap(parent) != nil
        case .current: true
        case .onKeyboard: running != nil
        case let .revision(id): id != selected?.id && session.revisions.contains { $0.id == id }
        }
    }

    /// Why the page has nothing to show (`shown` is nil): no revisions yet, or the selected one is loading or unreadable.
    var unavailable: String {
        if selected == nil { return String(localized: "No revisions yet") }
        return error == nil ? String(localized: "Loading revisions…") : String(localized: "This revision couldn’t be read")
    }

    func title(_ comparison: Comparison) -> String {
        switch comparison {
        case .parent: String(localized: "Previous revision")
        case .current: String(localized: "Current")
        case .onKeyboard: String(localized: "On keyboard")
        case let .revision(id): session.revisions.first { $0.id == id }.map { String(localized: "Revision \($0.number)") } ?? ""
        }
    }

    /// The selected revision and its changes; nil until its layout loads.
    var shown: Shown? {
        guard let revision = selected, let layout = layouts[revision.id] else { return nil }
        // The keyboard's revision, or its working copy as of the library's last refresh (ADR 0039).
        let keyboard = running.map { "\($0.revision?.id ?? "")@\($0.entry.modifiedAt.timeIntervalSince1970)" }
        let key = MemoKey(
            revision: revision.id, comparison: comparison, loaded: layouts.count, edits: comparison == .current ? session.changeCount : 0,
            keyboard: comparison == .onKeyboard ? keyboard : nil)
        if let memo, memo.key == key { return memo.shown }
        let base = base(comparison)
        let changes = base.map { layout.changes(from: $0) }
        var marks: [KeyRef: KeyChange] = [:]
        for change in changes?.diff.keyChanges ?? [] { marks[KeyRef(layer: change.layer, index: change.index)] = change }
        let shown = Shown(revision: revision, layout: layout, base: base, changes: changes, marks: marks)
        memo = (key, shown)
        return shown
    }

    /// A cap on the Changes board (spec §4.7): added, changed or removed, ringed in the same color; unchanged keys are
    /// quiet. With nothing to compare, every cap is plain.
    func decoration(layer: Int, index: Int) -> CapDecoration {
        guard let shown, shown.changes != nil else { return CapDecoration() }
        guard let change = shown.marks[KeyRef(layer: layer, index: index)] else { return CapDecoration(opacity: 0.4) }
        let mark = Self.mark(change.kind)
        return CapDecoration(ring: mark.color, badge: mark)
    }

    static func mark(_ kind: KeyChange.Kind) -> CapDecoration.Mark {
        switch kind {
        case .added: CapDecoration.Mark(symbol: "plus.circle.fill", color: Tokens.success, accessibilityText: String(localized: "Added"))
        case .modified: CapDecoration.Mark(symbol: "circle.fill", color: Tokens.warning, accessibilityText: String(localized: "Changed"))
        case .removed:
            CapDecoration.Mark(symbol: "minus.circle.fill", color: Tokens.danger, accessibilityText: String(localized: "Removed"))
        }
    }

    // MARK: The board's layer

    /// The Changes board's layer of `layout`: a layer only the revision has while it is pinned, else the selected layer
    /// by id, else the selected index, clamped. Layers match by id, so a revision with other layers never shows the
    /// wrong one.
    func shownLayer(in layout: KeyboardLayout) -> Int {
        if let pin = pinnedLayer, let i = layout.layers.firstIndex(where: { $0.id == pin }) { return i }
        if let id = session.currentLayer?.id, let i = layout.layers.firstIndex(where: { $0.id == id }) { return i }
        return min(session.selection.layer, max(layout.layers.count - 1, 0))
    }

    /// Shows a layer of the revision: the document's layer with its id, or, when the document no longer has it, that
    /// layer pinned until another one is chosen.
    func show(layer index: Int, of layout: KeyboardLayout) {
        guard let id = layout.layers[safe: index]?.id else { return }
        if let i = session.layout.layers.firstIndex(where: { $0.id == id }) {
            pinnedLayer = nil
            session.select(layer: i)
        } else {
            pinnedLayer = id
        }
    }

    // MARK: Actions

    /// Restore makes a new revision, so it is off for one the document already equals (bar its title).
    func canRestore(_ revision: RevisionSummary) -> Bool {
        guard var layout = layouts[revision.id] else { return false }
        layout.title = session.layout.title
        return layout != session.layout
    }

    func restore(_ revision: RevisionSummary) async {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }
        error = nil
        do throws(LibraryError) {
            try await session.restoreRevision(revision)
            selectedID = nil
            pinnedLayer = nil
        } catch {
            self.error = error
        }
    }

    /// Opens Save Revision with a message suggested from the changes since the last revision, the only one it reads.
    func beginSave() async {
        guard session.isEditedSinceRevision else { return }
        var last = session.revisions.last.flatMap { layouts[$0.id] }
        if last == nil, let revision = session.revisions.last {
            // Unreadable, the sheet still opens, without a suggestion.
            last = try? await session.revisionLayout(revision.id)
        }
        saveMessage = last.map { Self.message(for: session.layout.changes(from: $0), in: session.layout) } ?? ""
    }

    /// Records the document as a revision; a blank message stores none.
    func save(message: String) async throws(LibraryError) {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        try await session.saveRevision(source: .save, message: text.isEmpty ? nil : text)
        saveMessage = nil
        selectedID = nil
    }

    /// Save Revision's suggestion (spec §8.7): "Edited 5 keys on Brd+Sys", "Edited 12 keys on 3 layers", "Changed 2
    /// settings". Keys come first; otherwise the first other kind of change.
    static func message(for changes: LayoutChanges, in layout: KeyboardLayout) -> String {
        let keys = changes.diff.keyChanges
        let layers = Set(keys.map(\.layerID))
        if let first = keys.first {
            guard layers.count == 1 else { return String(localized: "Edited \(keys.count) keys on \(layers.count) layers") }
            let name = layout.layers.first { $0.id == first.layerID }?.title ?? ""
            return keys.count == 1
                ? String(localized: "Edited 1 key on \(name)") : String(localized: "Edited \(keys.count) keys on \(name)")
        }
        let diff = changes.diff
        if !(diff.addedLayers.isEmpty && diff.removedLayers.isEmpty && diff.renamedLayers.isEmpty && diff.recoloredLayers.isEmpty)
            || changes.layersMoved
        {
            return String(localized: "Edited layers")
        }
        if !changes.settings.isEmpty {
            return changes.settings.count == 1
                ? String(localized: "Changed 1 setting") : String(localized: "Changed \(changes.settings.count) settings")
        }
        if !(changes.addedCombos.isEmpty && changes.removedCombos.isEmpty) { return String(localized: "Edited combos") }
        if changes.navigatorChanged { return String(localized: "Changed the Navigator") }
        return changes.titleChanged ? String(localized: "Renamed the layout") : ""
    }

    /// Where a revision came from: "Imported from Oryx".
    static func describe(_ source: RevisionSource) -> String {
        switch source {
        case .import: String(localized: "Imported from Oryx")
        case .flash: String(localized: "Flashed from Sextant")
        case .save: String(localized: "Saved in Sextant")
        }
    }

    /// A revision's message, or where it came from when it has none.
    static func line(_ revision: RevisionSummary) -> String { revision.message ?? describe(revision.source) }
}

extension LayoutWindowModel {
    /// ⌘S needs edits since the last revision (spec §9.1).
    var canSaveRevision: Bool { session?.isEditedSinceRevision == true && history?.saveMessage == nil }

    /// File ▸ Save Revision…: opens the sheet once its message is worked out. Snapshots, which run no tasks, wait for it.
    public func beginSaveRevision() async {
        guard canSaveRevision, let history else { return }
        await history.beginSave()
    }

    /// Shows a revision on the History page (the palette's Documents rows) and loads what it compares. Snapshots, which
    /// run no tasks, wait for it.
    public func showRevision(_ id: String) async {
        history?.selectedID = id
        destination = .history
        await history?.load()
    }

    /// The palette's Documents rows for revisions (spec §5.7): "Revision 3 · Edited 5 keys on Brd+Sys".
    func revisionItems(_ query: String) -> [PaletteItem] {
        guard let revisions = session?.revisions else { return [] }
        let found = revisions.reversed().compactMap { revision -> (Int, RevisionSummary)? in
            let title = String(localized: "Revision \(revision.number)")
            let score = PaletteSearch.score(query, [title, HistoryModel.line(revision), revision.id])
            return score > 0 ? (score, revision) : nil
        }
        return found.sorted { $0.0 > $1.0 }.prefix(5).map { _, revision in
            PaletteItem(
                id: "revision-\(revision.id)", group: .documents, title: String(localized: "Revision \(revision.number)"),
                detail: revision.createdAt.formatted(date: .abbreviated, time: .omitted), note: HistoryModel.line(revision),
                leading: .symbol("clock.arrow.circlepath")
            ) { [weak self] in
                self?.palette = nil
                Task { await self?.showRevision(revision.id) }
            }
        }
    }
}
