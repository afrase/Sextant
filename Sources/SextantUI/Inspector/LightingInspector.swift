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
            Divider()
            KeyboardLightingSection(model: model)
        }
    }
}

/// "On the keyboard" (spec §6.2, ADR 0051): the preview switch, its brightness, and why it can't start.
private struct KeyboardLightingSection: View {
    var model: LayoutWindowModel

    var body: some View {
        let refusal = model.previewsLighting ? nil : model.lightingPreviewRefusal
        Text("On the keyboard").font(.headline)
        HStack {
            Text("Preview on Keyboard").foregroundStyle(refusal == nil ? .primary : .secondary).accessibilityHidden(true)
            Spacer()
            Toggle("Preview on Keyboard", isOn: Binding(get: { model.previewsLighting }, set: { model.previewsLighting = $0 }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityHint(refusal?.localizedDescription ?? "")
        }
        .disabled(refusal != nil)
        if let refusal {
            Text(refusal.localizedDescription).font(.callout).foregroundStyle(.secondary)
            if refusal == .liveOff {
                Button("Turn On Live View") { model.isLive = true }.controlSize(.small).disabled(!model.canGoLive)
            }
        } else if let pause = model.lightingPreviewPause {
            Text(pause).font(.callout).foregroundStyle(.secondary)
        }
        let brightness = model.lightingPreview?.brightness ?? 1
        let percent = Text(brightness, format: .percent.precision(.fractionLength(0)))
        HStack(spacing: 8) {
            Text("Brightness").accessibilityHidden(true)
            Slider(
                value: Binding(get: { brightness }, set: { model.lightingPreview?.setBrightness($0) }),
                in: LightingPreview.brightnessRange
            ) {
                Text("Brightness")
            }
            .labelsHidden()
            .controlSize(.small)
            .accessibilityValue(percent)
            percent.monospacedDigit().frame(width: 40, alignment: .trailing).accessibilityHidden(true)
        }
        .disabled(model.lightingPreview == nil)
        Text(
            """
            Shows this layer’s colors on the keyboard as you paint. Nothing is saved to it until you flash, and the \
            preview ends when you leave Lighting. It stays dark while the keyboard’s lights are off: turned off with its \
            own key, or by Lights off when idle in Firmware Settings.
            """
        )
        .font(.callout).foregroundStyle(.secondary)
    }
}
