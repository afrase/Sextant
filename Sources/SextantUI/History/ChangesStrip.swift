import SextantApplication
import SextantDomain
import SwiftUI

/// The History destination's centre (spec §2.2): the canvas with the Changes board. It loads the revisions it compares
/// whenever one is added.
struct HistoryCanvas: View {
    var model: LayoutWindowModel
    var session: EditSession

    var body: some View {
        CanvasColumn(model: model, session: session)
            .navigationTitle(session.layout.title)
            .navigationSubtitle(session.isEditedSinceRevision ? String(localized: "History · Edited") : String(localized: "History"))
            .task(id: session.revisions.count) { await model.history?.load() }
    }
}

extension HistoryModel {
    /// The Changes board: the selected revision on its shown layer, or the document until the revision loads; read-only
    /// either way.
    var display: BoardDisplay {
        guard let layout = shown?.layout else { return BoardDisplay(layout: session.layout, layer: session.selection.layer) }
        return BoardDisplay(layout: layout, layer: shownLayer(in: layout))
    }
}

/// The Changes board (spec §8.7): the selected revision against its comparison, read-only, in the document's geometry,
/// so no key moves. Public for snapshots of its accessibility variants (spec §11).
public struct ChangesBoard: View {
    var model: LayoutWindowModel
    var showsGrid = true

    public init(model: LayoutWindowModel) { self.model = model }

    init(model: LayoutWindowModel, showsGrid: Bool) {
        self.model = model
        self.showsGrid = showsGrid
    }

    public var body: some View {
        if let session = model.session {
            BoardView(
                session: session, mode: model.legendMode, pressed: model.pressedKeys, highlightedKind: model.highlightedKind,
                showsGrid: showsGrid
            )
            .environment(\.boardDisplay, model.history?.display ?? BoardDisplay(layout: session.layout, layer: session.selection.layer))
            .environment(\.layoutWindow, model)
        }
    }
}

/// "Compare with: Previous revision ▾" (spec §3.7), in place of the lens picker.
struct CompareMenu: View {
    var history: HistoryModel

    var body: some View {
        Menu {
            ForEach([HistoryModel.Comparison.parent, .current, .onKeyboard], id: \.self) { comparison in
                toggle(comparison, title: history.title(comparison))
            }
            Menu("Another Revision") {
                ForEach(history.session.revisions.reversed().filter { $0.id != history.selected?.id }) { revision in
                    toggle(.revision(revision.id), title: "\(history.title(.revision(revision.id))) · \(HistoryModel.line(revision))")
                }
            }
        } label: {
            Text("Compare with: \(history.title(history.comparison))")
        }
        .menuStyle(.button)
        .controlSize(.small)
        .fixedSize()
    }

    private func toggle(_ comparison: HistoryModel.Comparison, title: String) -> some View {
        Toggle(title, isOn: Binding(get: { history.comparison == comparison }, set: { _ in history.comparison = comparison }))
            .disabled(!history.canCompare(with: comparison))
    }
}

/// The lens lane's History capsule (spec §3.7): what the badges mean, with the revision's counts, or why there is
/// nothing to compare.
struct HistoryCapsule: View {
    var history: HistoryModel

    var body: some View {
        HStack(spacing: 10) {
            if let revision = history.selected {
                Text("Revision \(revision.number)")
            }
            if let changes = history.shown?.changes {
                let kinds = Dictionary(grouping: changes.diff.keyChanges, by: \.kind).mapValues(\.count)
                ForEach([KeyChange.Kind.added, .modified, .removed], id: \.self) { kind in
                    let mark = HistoryModel.mark(kind)
                    HStack(spacing: 4) {
                        Image(systemName: mark.symbol).foregroundStyle(mark.color.color).accessibilityHidden(true)
                        Text(Self.count(kinds[kind] ?? 0, kind))
                    }
                    .accessibilityElement(children: .combine)
                }
                let others = changes.count - changes.diff.keyChanges.count
                if others > 0 {
                    Text(others == 1 ? String(localized: "1 other change") : String(localized: "\(others) other changes"))
                        .foregroundStyle(.secondary)
                }
            } else if history.shown != nil {
                Text(nothingToCompare).foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .font(.callout.weight(.medium))
        .padding(.horizontal, 12)
        .frame(height: 28)
        .surface(Capsule(), interactive: true)
    }

    private var nothingToCompare: String {
        switch history.comparison {
        case .parent: String(localized: "The first revision: nothing before it")
        case .onKeyboard: String(localized: "The keyboard doesn’t run this layout")
        case .current, .revision: String(localized: "Nothing to compare")
        }
    }

    static func count(_ n: Int, _ kind: KeyChange.Kind) -> String {
        switch kind {
        case .added: String(localized: "\(n) added")
        case .modified: String(localized: "\(n) changed")
        case .removed: String(localized: "\(n) removed")
        }
    }
}

/// The context strip on History (spec §3.7): each of the revision's layers with its change count; a click shows the
/// layer. Layers the comparison has and the revision lacks follow, dashed.
struct ChangesStrip: View {
    var history: HistoryModel

    var body: some View {
        if let shown = history.shown, let changes = shown.changes {
            let current = history.shownLayer(in: shown.layout)
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(Array(shown.layout.layers.enumerated()), id: \.element.id) { index, layer in
                            Button {
                                history.show(layer: index, of: shown.layout)
                            } label: {
                                card(layer, line: line(layer, index: index, changes: changes), dashed: false, current: index == current)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(index == current ? .isSelected : [])
                        }
                        ForEach(changes.diff.removedLayers) { layer in
                            card(layer, line: String(localized: "Removed"), dashed: true, current: false)
                        }
                    }
                    .padding(.horizontal, 20)
                    .frame(maxHeight: .infinity)
                }
                .scrollIndicators(.never)
                .onAppear { if let id = shown.layout.layers[safe: current]?.id { proxy.scrollTo(id, anchor: .center) } }
                .onChange(of: current) { if let id = shown.layout.layers[safe: current]?.id { proxy.scrollTo(id, anchor: .center) } }
            }
        } else {
            Text(history.shown == nil ? String(localized: "Loading revisions…") : String(localized: "Choose what to compare with above"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func line(_ layer: Layer, index: Int, changes: LayoutChanges) -> String {
        let n = changes.diff.changes(onLayer: index).count
        if changes.diff.addedLayers.contains(where: { $0.id == layer.id }) {
            return n == 1 ? String(localized: "New layer · 1 key") : String(localized: "New layer · \(n) keys")
        }
        switch n {
        case 0: return String(localized: "No changes")
        case 1: return String(localized: "1 change")
        default: return String(localized: "\(n) changes")
        }
    }

    private func card(_ layer: Layer, line: String, dashed: Bool, current: Bool) -> some View {
        HStack(spacing: 8) {
            LayerChip(color: layer.color, size: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(layer.title).font(.callout.weight(.medium)).lineLimit(1)
                Text(line).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .frame(minWidth: 150, maxHeight: 60, alignment: .leading)
        .background(ContextStrip.card(dashed: dashed, current: current))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The sidebar's History row (spec §3.6) with its revision count.
struct HistoryRow: View {
    var revisions: Int
    var isSelected: Bool

    var body: some View {
        // The selected row's fill is dark grey in dark mode; a secondary badge vanishes on it (as in LayersSection).
        Label("History", systemImage: "clock.arrow.circlepath")
            .badge(revisions == 0 ? nil : Text(verbatim: "\(revisions)").foregroundStyle(isSelected ? .primary : .secondary))
            .accessibilityValue(revisions == 1 ? String(localized: "1 revision") : String(localized: "\(revisions) revisions"))
    }
}
