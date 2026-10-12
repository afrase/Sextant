import SextantApplication
import SextantDomain
import SwiftUI

/// The History inspector (spec §8.7): the timeline, then the selected revision's details, its changes by layer and key,
/// and Restore.
struct HistoryInspector: View {
    var model: LayoutWindowModel

    var body: some View {
        if let history = model.history {
            if history.session.revisions.isEmpty {
                ContentUnavailableView {
                    Label("No Revisions", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("Revisions appear when you import, flash, or save a revision (⌘S).")
                } actions: {
                    Button("Save Revision…") { Task { await model.beginSaveRevision() } }.disabled(!model.canSaveRevision)
                }
            } else {
                Text("Revisions").font(.headline)
                Timeline(history: history)
                if let shown = history.shown {
                    Divider()
                    RevisionDetails(history: history, shown: shown)
                }
                if let error = history.error {
                    Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(Tokens.danger.color)
                }
            }
        }
    }
}

/// Newest first: a node on a line, the id in mono, its badges, the message, the date and the change count.
private struct Timeline: View {
    var history: HistoryModel
    /// The row the scrolling timeline centers on: the selected one, as when the palette chooses a revision.
    @State private var position: String?

    var body: some View {
        // Every flash adds a row: past a few, the timeline scrolls on its own so the selected revision's details stay in view.
        if history.session.revisions.count > 4 {
            ScrollView { rows.scrollTargetLayout() }
                .scrollPosition(id: $position, anchor: .center)
                .frame(height: 250)
                .onAppear { position = history.selected?.id }
                .onChange(of: history.selected?.id) { position = history.selected?.id }
        } else {
            rows
        }
    }

    private var rows: some View {
        let revisions = Array(history.session.revisions.reversed())
        let onKeyboard = history.running?.revision?.id
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(revisions.enumerated()), id: \.element.id) { n, revision in
                let isSelected = revision.id == history.selected?.id
                let isOnKeyboard = revision.id == onKeyboard
                Button {
                    history.selectedID = revision.id
                    history.pinnedLayer = nil
                } label: {
                    row(revision, isSelected: isSelected, isOnKeyboard: isOnKeyboard, isOldest: n == revisions.count - 1)
                }
                .buttonStyle(.plain)
                // Named as everywhere else ("Revision 2"), not by the id a screen reader would spell out.
                .accessibilityLabel(
                    ([String(localized: "Revision \(revision.number)"), HistoryModel.line(revision)]
                        + (isOnKeyboard ? [String(localized: "on keyboard")] : [])).joined(separator: ", ")
                )
                .accessibilityValue(subtitle(revision))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private func row(_ revision: RevisionSummary, isSelected: Bool, isOnKeyboard: Bool, isOldest: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(isSelected ? Color.accentColor : Tokens.neutralChip.color)
                .frame(width: 9, height: 9)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 3) {
                let id = Text(verbatim: revision.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                let badges = HStack(spacing: 5) {
                    RevisionBadge(text: revision.source == .import ? String(localized: "ORYX") : String(localized: "LOCAL"), tint: nil)
                    if isOnKeyboard { RevisionBadge(text: String(localized: "ON KEYBOARD"), tint: Tokens.success) }
                }
                // The badges wrap under the id rather than cut it short in a narrow inspector.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 5) {
                        id
                        badges
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        id
                        badges
                    }
                }
                Text(HistoryModel.line(revision)).font(.callout).lineLimit(2)
                Text(subtitle(revision)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        // The line joins each node to the next, older one.
        .background(alignment: .leading) {
            Rectangle()
                .fill(.quaternary)
                .frame(width: 1)
                .padding(.leading, 10)
                .padding(.top, 18)
                .padding(.bottom, -6)
                .opacity(isOldest ? 0 : 1)
        }
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(isSelected ? Color.accentColor.opacity(0.12) : .clear))
        .contentShape(Rectangle())
    }

    private func subtitle(_ revision: RevisionSummary) -> String {
        let date = revision.createdAt.formatted(date: .abbreviated, time: .shortened)
        switch history.counts[revision.id] {
        case nil: return date
        case 0: return String(localized: "\(date) · no changes")
        case 1: return String(localized: "\(date) · 1 change")
        case let n?: return String(localized: "\(date) · \(n) changes")
        }
    }
}

/// ORYX, LOCAL or ON KEYBOARD (spec §8.7): small caps in a tinted capsule; neutral without a tint.
private struct RevisionBadge: View {
    var text: String
    var tint: Token?

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(tint?.color ?? Color.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Capsule().fill((tint?.color ?? Color.secondary).opacity(0.15)))
            .fixedSize()
    }
}

/// The selected revision: where it came from, what changed against the comparison, and Restore.
private struct RevisionDetails: View {
    var history: HistoryModel
    var shown: HistoryModel.Shown

    var body: some View {
        let revision = shown.revision
        let date = revision.createdAt.formatted(date: .abbreviated, time: .shortened)
        VStack(alignment: .leading, spacing: 4) {
            Text("Revision \(revision.number)").font(.title3.weight(.semibold))
            Text(verbatim: "\(HistoryModel.describe(revision.source)) · \(date)").font(.callout).foregroundStyle(.secondary)
            if let message = revision.message { Text(message).font(.callout) }
        }
        if let changes = shown.changes {
            Divider()
            Text("Changes").font(.headline)
            if changes.isEmpty {
                Text("No changes").font(.callout).foregroundStyle(.secondary)
            } else {
                LayerBreakdown(history: history, shown: shown, changes: changes)
                OtherChanges(changes: changes)
                KeyChangesTable(history: history, shown: shown, changes: changes)
            }
        }
        Divider()
        Button("Restore This Revision") { Task { await history.restore(revision) } }
            .disabled(!history.canRestore(revision) || history.isRestoring)
        Text("Makes this revision the layout again and saves that as a new revision. Nothing is lost, and you can undo it.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The per-layer bar (spec §8.7): one bar, each layer as wide as its share of the changed keys, then each layer's count.
private struct LayerBreakdown: View {
    var history: HistoryModel
    var shown: HistoryModel.Shown
    var changes: LayoutChanges

    var body: some View {
        let layers = shown.layout.layers.enumerated().compactMap { index, layer -> (index: Int, layer: Layer, count: Int)? in
            let n = changes.diff.changes(onLayer: index).count
            return n == 0 ? nil : (index, layer, n)
        }
        if !layers.isEmpty {
            let total = CGFloat(layers.reduce(0) { $0 + $1.count })
            GeometryReader { proxy in
                let width = proxy.size.width - CGFloat(layers.count - 1) * 2
                HStack(spacing: 2) {
                    ForEach(layers, id: \.layer.id) { item in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(item.layer.color.map { LayerTones($0).display.color } ?? Tokens.neutralChip.color)
                            .frame(width: max(3, width * CGFloat(item.count) / total))
                    }
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
            ForEach(layers, id: \.layer.id) { item in
                Button {
                    history.show(layer: item.index, of: shown.layout)
                } label: {
                    HStack(spacing: 6) {
                        LayerChip(color: item.layer.color, size: 10)
                        Text(item.layer.title).lineLimit(1)
                        Spacer()
                        Text(item.count == 1 ? String(localized: "1 key") : String(localized: "\(item.count) keys"))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Changes that aren't keys: layers, settings, combos and the Navigator.
private struct OtherChanges: View {
    var changes: LayoutChanges

    var body: some View {
        let lines = Self.lines(changes)
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(lines, id: \.self) { Label($0, systemImage: "circle.fill").labelStyle(BulletStyle()) }
            }
            .font(.callout)
        }
    }

    static func lines(_ changes: LayoutChanges) -> [String] {
        let diff = changes.diff
        var lines = changes.titleChanged ? [String(localized: "Renamed the layout")] : []
        lines += diff.addedLayers.map { String(localized: "Added layer \($0.title)") }
        lines += diff.removedLayers.map { String(localized: "Removed layer \($0.title)") }
        lines += diff.renamedLayers.map { String(localized: "Renamed layer \($0.from) to \($0.to)") }
        if changes.layersMoved { lines.append(String(localized: "Reordered layers")) }
        if !diff.recoloredLayers.isEmpty {
            lines.append(
                diff.recoloredLayers.count == 1
                    ? String(localized: "Changed 1 layer color") : String(localized: "Changed \(diff.recoloredLayers.count) layer colors"))
        }
        if !changes.settings.isEmpty {
            let names = changes.settings.map { SettingsCatalog.voyager.setting(id: $0)?.title ?? $0 }.formatted(.list(type: .and))
            lines.append(String(localized: "Settings: \(names)"))
        }
        if !changes.addedCombos.isEmpty {
            lines.append(
                changes.addedCombos.count == 1
                    ? String(localized: "Added 1 combo") : String(localized: "Added \(changes.addedCombos.count) combos"))
        }
        if !changes.removedCombos.isEmpty {
            lines.append(
                changes.removedCombos.count == 1
                    ? String(localized: "Removed 1 combo") : String(localized: "Removed \(changes.removedCombos.count) combos"))
        }
        if changes.navigatorChanged { lines.append(String(localized: "Changed the Navigator")) }
        return lines
    }
}

private struct BulletStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon.font(.system(size: 4)).foregroundStyle(.secondary).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 3 }
            configuration.title
        }
    }
}

/// The changes table (spec §8.7): each changed key, its cap before and after, and what changed. A row shows its layer and
/// selects the key.
private struct KeyChangesTable: View {
    var history: HistoryModel
    var shown: HistoryModel.Shown
    var changes: LayoutChanges
    /// Enough to read; a whole new layout can change hundreds of keys.
    private let limit = 60

    var body: some View {
        let rows = changes.diff.keyChanges.sorted { ($0.layer, $0.index) < ($1.layer, $1.index) }
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(rows.prefix(limit).enumerated()), id: \.element.id) { n, change in
                if n == 0 || rows[n - 1].layer != change.layer {
                    Text(shown.layout.layers[safe: change.layer]?.title ?? "").font(.subheadline.weight(.semibold)).padding(.top, 6)
                }
                Button {
                    history.show(layer: change.layer, of: shown.layout)
                    history.session.select(key: change.index)
                } label: {
                    row(change)
                }
                .buttonStyle(.plain)
            }
            if rows.count > limit {
                Text("and \(rows.count - limit) more").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ change: KeyChange) -> some View {
        let mark = HistoryModel.mark(change.kind)
        let before = shown.base.flatMap { base in base.layers.firstIndex { $0.id == change.layerID }.map { (base, $0) } }
        return HStack(spacing: 6) {
            Image(systemName: mark.symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(mark.color.color)
            Text("key \(change.index)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 46, alignment: .leading)
            cap(before.map { KeyCapModel(layout: $0.0, layer: $0.1, index: change.index) })
            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary).accessibilityHidden(true)
            cap(KeyCapModel(layout: shown.layout, layer: change.layer, index: change.index))
            Text(Self.what(change)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Key \(change.index), \(mark.accessibilityText): \(Self.what(change))"))
    }

    @ViewBuilder private func cap(_ model: KeyCapModel?) -> some View {
        if let model {
            KeyCap(model: model, u: 28).frame(width: 28, height: 28)
        } else {
            RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                .strokeBorder(Tokens.ghostStroke.color, style: StrokeStyle(lineWidth: 1, dash: [3, 2.5]))
                .frame(width: 28, height: 28)
        }
    }

    /// "Tap, Hold · label · color".
    static func what(_ change: KeyChange) -> String {
        var parts = change.changedSlots.isEmpty ? [] : [change.changedSlots.map(\.title).joined(separator: ", ")]
        if change.labelChanged { parts.append(String(localized: "label")) }
        if change.colorChanged { parts.append(String(localized: "color")) }
        return parts.joined(separator: " · ")
    }
}
