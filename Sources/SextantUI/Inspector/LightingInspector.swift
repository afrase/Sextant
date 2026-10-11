import SextantApplication
import SextantDomain
import SwiftUI

/// The Lighting lens inspector (spec §3.8, §6.2): the brush, and the shown layer's lighting.
struct LightingInspector: View {
    var model: LayoutWindowModel
    var session: EditSession

    var body: some View {
        let index = session.selection.layer
        if let layer = session.currentLayer {
            let painted = model.keysWithOwnColour(on: index).count
            Text("Brush").font(.headline)
            HStack(spacing: 8) {
                if model.isErasing {
                    Image(systemName: "eraser").accessibilityHidden(true)
                    Text("Eraser · no own color")
                } else {
                    LayerChip(color: model.brushColor, size: 14)
                    Text(verbatim: model.brushColor.hex).monospaced()
                }
            }
            BrushSwatches(model: model)
            HStack(spacing: 8) {
                Text("Custom").foregroundStyle(.secondary)
                BrushColorPicker(model: model)
                Spacer()
                EraserToggle(model: model)
            }
            Divider()
            Text("Layer color").font(.headline)
            HStack(spacing: 8) {
                LayerChip(color: layer.color, size: 14)
                Text(layer.color?.hex ?? String(localized: "No color")).monospaced()
                Spacer()
                Button("Use Brush") { session.setLayerColor(model.brushColor, layer: index) }
                    .disabled(model.isErasing || layer.color == model.brushColor)
                Button("None") { session.setLayerColor(nil, layer: index) }.disabled(layer.color == nil)
            }
            .controlSize(.small)
            Text("The layer color is also its LED color on the keyboard.").font(.callout).foregroundStyle(.secondary)
            Divider()
            Text("Painted on \(layer.title)").font(.headline)
            Text("\(painted) of \(layer.keys.count) keys have their own color").monospacedDigit()
            Button("Clear Key Colors…") { model.keyColoursPendingClear = index }.disabled(painted == 0)
        }
    }
}
