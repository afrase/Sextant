import SextantApplication
import SextantDomain
import SwiftUI

/// The open layout's layers, each a destination, and Add Layer (spec §3.6, §6.1). Drag to reorder; double-click
/// renames in place.
struct LayersSection: View {
    var model: LayoutWindowModel
    var session: EditSession

    var body: some View {
        // Another layout's layer numbers mean other layers.
        let liveLayer = model.runsThisLayout ? model.live?.activeLayer : nil
        Section("Layers") {
            ForEach(Array(session.layout.layers.enumerated()), id: \.element.id) { index, layer in
                LayerRow(model: model, index: index, layer: layer, isSelected: index == session.selection.layer, isLive: liveLayer == index)
                    .tag(Destination.layer(index))
                    // Item-based menus (`contextMenu(forSelectionType:)`) only work on the List itself, not inside it.
                    .contextMenu { LayerContextMenu(model: model, session: session, index: index) }
            }
            .onMove { model.moveLayer(fromOffsets: $0, toOffset: $1) }
            Button {
                model.addLayer()
            } label: {
                Label("Add Layer", systemImage: "plus")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }
}

private struct LayerContextMenu: View {
    var model: LayoutWindowModel
    var session: EditSession
    var index: Int

    var body: some View {
        Button("Rename…") { model.startRenaming(layer: index) }
        Menu("Colour") { LayerColourMenu(model: model, layer: index) }
        Divider()
        Button("Duplicate") { session.duplicateLayer(index) }
        Button("Move Up") { session.moveLayer(from: index, to: index - 1) }.disabled(index == 0)
        Button("Move Down") { session.moveLayer(from: index, to: index + 1) }
            .disabled(index == session.layout.layers.count - 1)
        Divider()
        Button("Copy Layer To…") {}.disabled(true)
        Button("Clear Layer…") { model.layerPendingClear = index }
        Button("Delete Layer…") {
            session.select(layer: index)
            model.requestDeleteLayer()
        }
        .disabled(!model.canDeleteLayer)
    }
}

private struct LayerRow: View {
    var model: LayoutWindowModel
    var index: Int
    var layer: Layer
    var isSelected: Bool
    /// The keyboard is on this layer (spec §3.6 live badge).
    var isLive = false
    @State private var draft = ""
    @FocusState private var isEditing: Bool

    var body: some View {
        let renaming = model.renamingLayerID == layer.id
        // The selected row's fill is dark grey in dark mode; secondary text and badges vanish on it.
        let detail: HierarchicalShapeStyle = isSelected ? .primary : .secondary
        HStack(spacing: 8) {
            LayerChip(color: layer.color, size: 10)
            Text(verbatim: "\(index)").monospacedDigit().foregroundStyle(detail)
            if renaming {
                TextField("Layer name", text: $draft)
                    .focused($isEditing)
                    .onAppear {
                        draft = layer.title
                        isEditing = true
                    }
                    .onSubmit { model.finishRenaming(layer.id, to: draft) }
                    .onExitCommand { model.renamingLayerID = nil }
                    .onChange(of: isEditing) { if !isEditing { model.finishRenaming(layer.id, to: draft) } }
            } else {
                Text(layer.title)
            }
            if isLive { Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(Tokens.success.color) }
        }
        // The whole row takes the double-click, not just its text; while renaming, the field gets it (word selection).
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .gesture(TapGesture(count: 2).onEnded { model.startRenaming(layer: index) }, isEnabled: !renaming)
        .badge(Text(verbatim: "\(layer.keys.filter { !$0.isTransparent }.count)").foregroundStyle(detail))
        .accessibilityElement(children: renaming ? .contain : .combine)
        .accessibilityLabel(
            isLive
                ? String(localized: "Layer \(index), \(layer.title), the keyboard’s layer")
                : String(localized: "Layer \(index), \(layer.title)"))
    }
}
