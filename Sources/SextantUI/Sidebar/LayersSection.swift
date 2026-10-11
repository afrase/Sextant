import SextantApplication
import SextantDomain
import SwiftUI

/// The open layout's layers, each a destination, and Add Layer (spec §3.6, §6.1).
struct LayersSection: View {
    var model: LayoutWindowModel
    var session: EditSession

    var body: some View {
        Section("Layers") {
            ForEach(Array(session.layout.layers.enumerated()), id: \.element.id) { index, layer in
                LayerRow(index: index, layer: layer, isLive: model.live?.activeLayer == index)
                    .tag(Destination.layer(index))
                    .contextMenu {
                        Button("Duplicate") { session.duplicateLayer(index) }
                        Button("Move Up") { session.moveLayer(from: index, to: index - 1) }.disabled(index == 0)
                        Button("Move Down") { session.moveLayer(from: index, to: index + 1) }
                            .disabled(index == session.layout.layers.count - 1)
                        Divider()
                        Button("Delete Layer…") {
                            session.select(layer: index)
                            model.requestDeleteLayer()
                        }
                        .disabled(!model.canDeleteLayer)
                    }
            }
            Button {
                session.addLayer()
            } label: {
                Label("Add Layer", systemImage: "plus")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }
}

private struct LayerRow: View {
    var index: Int
    var layer: Layer
    /// The keyboard is on this layer (spec §3.6 live badge).
    var isLive = false

    var body: some View {
        HStack(spacing: 8) {
            LayerChip(color: layer.color, size: 10)
            Text(verbatim: "\(index)").monospacedDigit().foregroundStyle(.secondary)
            Text(layer.title)
            if isLive { Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(Tokens.success.color) }
        }
        .badge(layer.keys.filter { !$0.isTransparent }.count)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isLive
                ? String(localized: "Layer \(index), \(layer.title), the keyboard’s layer")
                : String(localized: "Layer \(index), \(layer.title)"))
    }
}
