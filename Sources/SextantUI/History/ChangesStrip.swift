import SextantDomain
import SwiftUI

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
            Text(history.shown == nil ? history.unavailable : String(localized: "Choose what to compare with above"))
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
