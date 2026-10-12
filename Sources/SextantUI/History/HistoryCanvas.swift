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
            // A pinned revision-only layer lasts until another layer is chosen, here or on another page.
            .onChange(of: session.selection.layer) { model.history?.pinnedLayer = nil }
            .onDisappear { model.history?.pinnedLayer = nil }
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
    var showsGrid: Bool

    public init(model: LayoutWindowModel, showsGrid: Bool = true) {
        self.model = model
        self.showsGrid = showsGrid
    }

    public var body: some View {
        if let session = model.session, let history = model.history {
            BoardView(
                session: session, mode: model.legendMode, pressed: model.pressedKeys, highlightedKind: model.highlightedKind,
                showsGrid: showsGrid
            )
            .environment(\.boardDisplay, history.display)
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
        .disabled(history.selected == nil)
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
        if let revision = history.selected {
            capsule(revision)
        }
    }

    private func capsule(_ revision: RevisionSummary) -> some View {
        HStack(spacing: 10) {
            Text("Revision \(revision.number)")
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
            } else {
                Text(history.shown == nil ? history.unavailable : nothingToCompare).foregroundStyle(.secondary)
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
