import AppKit
import SextantApplication
import SextantDomain
import SwiftUI

/// What a Lighting-lens stroke gives the keys it crosses: a colour, or (nil, the eraser) no colour of their own.
struct Brush: Equatable {
    var color: HexColor?
}

extension EnvironmentValues {
    /// The Lighting lens brush, nil in every other lens. The window sets it (``LayerPresentations``) and the board
    /// paints with it instead of selecting (spec §2.2, §6.2).
    @Entry var brush: Brush?
}

/// Layer management (spec §6.1) and the Lighting lens (§6.2).
extension LayoutWindowModel {
    /// Inline rename needs the row on screen; Sextant never opens the sidebar itself (spec §2.2).
    var showsSidebar: Bool { columnVisibility != .detailOnly }

    /// The board's brush, in the Lighting lens only.
    var brush: Brush? { lens == .lighting ? lighting.brush : nil }

    /// The layout's swatches, or Sextant's own set when it has none (spec §10.1).
    var swatches: [HexColor] {
        guard let swatch = session?.layout.swatch, !swatch.isEmpty else { return KeyboardLayout.defaultSwatch }
        return swatch
    }

    /// New Layer (⇧⌘N): appends a layer and starts renaming it in place (spec §6.1).
    func addLayer() {
        guard let session else { return }
        let index = session.addLayer()
        if showsSidebar { startRenaming(layer: index) }
    }

    public func startRenaming(layer index: Int) {
        layers.renamingID = session?.layout.layers[safe: index]?.id
    }

    /// Ends renaming `id` in place, renaming the layer unless `title` is blank. Return and leaving the field both
    /// call it, so only the first call counts.
    func finishRenaming(_ id: String, to title: String) {
        guard layers.renamingID == id else { return }
        layers.renamingID = nil
        if let index = session?.layout.layers.firstIndex(where: { $0.id == id }) { session?.renameLayer(index, to: title) }
    }

    /// A sidebar drag (`onMove` offsets) as one "Move Layer" step; layer references follow (spec §3.6).
    func moveLayer(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard source.count == 1, let from = source.first else { return }
        session?.moveLayer(from: from, to: destination > from ? destination - 1 : destination)
    }

    /// Keys on `layer` with an LED colour of their own.
    func keysWithOwnColour(on layer: Int) -> [Int] {
        guard let keys = session?.layout.layers[safe: layer]?.keys else { return [] }
        return keys.indices.filter { keys[$0].glowColor != nil }
    }

    /// Clear Key Colours: the keys fall back to the layer colour, as one undo step.
    func clearKeyColours(on layer: Int) {
        session?.paint(nil, keys: keysWithOwnColour(on: layer), layer: layer)
    }
}

extension HexColor {
    /// A SwiftUI colour (a `ColorPicker`'s) as stored data, snapped to `#RRGGBB` so it survives the file unchanged.
    init?(_ color: Color) {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        self.init(hex: HexColor(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent).hex)
    }

    /// A swatch for menu items, which draw images but not views.
    var swatchImage: Image {
        let fill = NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            fill.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3).fill()
            return true
        }
        return Image(nsImage: image)
    }
}

/// Colour ▸ for a layer (spec §3.6, §6.1): the layout's swatches, Custom… and No Colour. The colour is also the
/// layer's LED colour on the keyboard.
struct LayerColourMenu: View {
    var model: LayoutWindowModel
    var layer: Int

    var body: some View {
        let current = model.session?.layout.layers[safe: layer]?.color
        ForEach(Array(model.swatches.enumerated()), id: \.offset) { _, color in
            Toggle(isOn: Binding(get: { current == color }, set: { _ in model.session?.setLayerColor(color, layer: layer) })) {
                Label {
                    Text(verbatim: color.hex)
                } icon: {
                    color.swatchImage
                }
            }
        }
        Divider()
        Button("Custom…") { model.lighting.layerPendingColour = layer }
        Button("No Color") { model.session?.setLayerColor(nil, layer: layer) }.disabled(current == nil)
    }
}

/// The layer confirmations and the Custom… colour sheet, and the brush the board paints with.
struct LayerPresentations: ViewModifier {
    var model: LayoutWindowModel

    func body(content: Content) -> some View {
        let lighting = model.lighting
        content
            .environment(\.brush, model.brush)
            .alert(
                Text("Clear \(layerName(model.layers.pendingClear))?"),
                isPresented: Binding(get: { model.layers.pendingClear != nil }, set: { _ in model.layers.pendingClear = nil }),
                presenting: model.layers.pendingClear
            ) { layer in
                Button("Clear Layer", role: .destructive) { model.session?.clearLayer(layer) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Every key on this layer becomes transparent and loses its own color. You can undo this.")
            }
            .alert(
                Text("Clear the key colors on \(layerName(lighting.keyColoursPendingClear))?"),
                isPresented: Binding(get: { lighting.keyColoursPendingClear != nil }, set: { _ in lighting.keyColoursPendingClear = nil }),
                presenting: lighting.keyColoursPendingClear
            ) { layer in
                Button("Clear Key Colors", role: .destructive) { model.clearKeyColours(on: layer) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("These keys go back to the layer color. You can undo this.")
            }
            .sheet(isPresented: Binding(get: { lighting.layerPendingColour != nil }, set: { _ in lighting.layerPendingColour = nil })) {
                if let layer = lighting.layerPendingColour { LayerColourSheet(model: model, layer: layer) }
            }
    }

    private func layerName(_ index: Int?) -> String {
        index.flatMap { model.session?.layout.layers[safe: $0]?.title } ?? ""
    }
}

/// Custom… layer colour. The picker edits a draft so dragging in the colour panel makes one undo step, not dozens.
struct LayerColourSheet: View {
    var model: LayoutWindowModel
    var layer: Int
    @State private var draft: Color
    @Environment(\.dismiss) private var dismiss

    init(model: LayoutWindowModel, layer: Int) {
        self.model = model
        self.layer = layer
        _draft = State(initialValue: (model.session?.layout.layers[safe: layer]?.color ?? model.lighting.brushColor).color)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Color for \(model.session?.layout.layers[safe: layer]?.title ?? "")").font(.headline)
            ColorPicker("Color", selection: $draft, supportsOpacity: false)
            Text("The layer color is also its LED color on the keyboard.").font(.callout).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Set Color") {
                    if let colour = HexColor(draft) { model.session?.setLayerColor(colour, layer: layer) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
