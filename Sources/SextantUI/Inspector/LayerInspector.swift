import SextantApplication
import SextantDomain
import SwiftUI

/// The layer summary when no key is selected (spec §3.8): name, colour, index, what reaches the layer, counts by
/// kind, and the layer actions.
struct LayerInspector: View {
    var model: LayoutWindowModel
    var session: EditSession

    var body: some View {
        let index = session.selection.layer
        if let layer = session.currentLayer {
            HStack(spacing: 8) {
                LayerChip(color: layer.color, size: 12)
                Text(layer.title).font(.title3.weight(.semibold))
            }
            Group {
                LabeledContent("Name") { LayerNameField(model: model, session: session, layer: layer).id(layer.id) }
                LabeledContent("Color") {
                    Menu {
                        LayerColourMenu(model: model, layer: index)
                    } label: {
                        Label {
                            Text(layer.color?.hex ?? String(localized: "No color"))
                        } icon: {
                            (layer.color ?? Tokens.neutralChip.light).swatchImage
                        }
                    }
                    .fixedSize()
                }
                LabeledContent("Index") { Text(verbatim: "\(index)").monospacedDigit() }
            }
            .labeledContentStyle(InspectorRowStyle())
            if let activator = KeyText.activator(layout: session.layout, layer: index) {
                let source = session.layout.layers[safe: activator.layer]?.title ?? ""
                let text = String(localized: "\(activator.text) on \(source)")
                Text(text.prefix(1).uppercased() + text.dropFirst()).font(.callout).foregroundStyle(.secondary)
            }
            Divider()
            Text("Keys").font(.headline)
            let counts = Dictionary(grouping: layer.keys, by: \.kind).mapValues(\.count)
            ForEach(KeyKind.allCases.filter { counts[$0] != nil }, id: \.self) { kind in
                LabeledContent(kind.title) { Text(verbatim: "\(counts[kind] ?? 0)").monospacedDigit() }
            }
            Divider()
            HStack {
                Button("Duplicate") { session.duplicateLayer(index) }
                Button("Copy To…") {}.disabled(true)
                Button("Clear…") { model.layerPendingClear = index }
            }
            Text("The layer color is also its LED color on the keyboard.").font(.callout).foregroundStyle(.secondary)
        }
    }
}

/// The layer's name. Return or leaving the field renames the layer it was made for (by id, so switching layers
/// mid-edit can't rename the next one); a blank name puts the old one back. A layout the window has let go isn't
/// renamed, as with the key label.
private struct LayerNameField: View {
    var model: LayoutWindowModel
    var session: EditSession
    let layerID: String
    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(model: LayoutWindowModel, session: EditSession, layer: Layer) {
        self.model = model
        self.session = session
        layerID = layer.id
        _draft = State(initialValue: layer.title)
    }

    var body: some View {
        let title = session.layout.layers.first { $0.id == layerID }?.title ?? ""
        TextField("Name", text: $draft)
            .labelsHidden()
            .focused($isFocused)
            .onSubmit(commit)
            .onChange(of: isFocused) { if !isFocused { commit() } }
            // Switching layers (⌘2) or closing the window replaces the field without a focus change.
            .onDisappear(perform: commit)
            .onChange(of: title) { draft = title }
    }

    private func commit() {
        guard model.session === session, let index = session.layout.layers.firstIndex(where: { $0.id == layerID }) else { return }
        session.renameLayer(index, to: draft)
        draft = session.layout.layers[index].title
    }
}
