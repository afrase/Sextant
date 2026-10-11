import SextantApplication
import SextantDomain
import SwiftUI

/// The Lighting lens tools capsule in the lens lane (spec §3.7, §6.2): the brush and the layer it paints.
struct LightingCapsule: View {
    var model: LayoutWindowModel
    var session: EditSession

    var body: some View {
        HStack(spacing: 8) {
            BrushSwatches(model: model)
            BrushColorPicker(model: model)
            EraserToggle(model: model)
            Text("Painting \(session.currentLayer?.title ?? "")").lineLimit(1)
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 12)
        .frame(height: 28)
        .surface(Capsule(), interactive: true)
    }
}

/// The layout's swatches as brush colours; the brush's is ringed.
struct BrushSwatches: View {
    var model: LayoutWindowModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(model.swatches.enumerated()), id: \.offset) { _, color in
                let current = !model.isErasing && model.brushColor == color
                Button {
                    model.pickBrush(color)
                } label: {
                    Circle()
                        .fill(color.color)
                        .overlay { Circle().strokeBorder(Tokens.capEdge.color, lineWidth: 0.5) }
                        .padding(current ? 2.5 : 1)
                        .overlay { if current { Circle().strokeBorder(Tokens.capLegend.color, lineWidth: 1.5) } }
                        .frame(width: 16, height: 16)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(color.hex)
                .accessibilityLabel(String(localized: "Brush color \(color.hex)"))
                .accessibilityAddTraits(current ? .isSelected : [])
            }
        }
    }
}

/// Custom… brush colour: the stock picker. The brush is window state, not an edit, so it applies live.
struct BrushColorPicker: View {
    var model: LayoutWindowModel

    var body: some View {
        ColorPicker(
            String(localized: "Custom Brush Color"),
            selection: Binding(get: { model.brushColor.color }, set: { HexColor($0).map(model.pickBrush) }),
            supportsOpacity: false
        )
        .labelsHidden()
        .controlSize(.small)
        .help(Text("Custom color"))
    }
}

/// The eraser: strokes remove keys' own colours, so they show the layer colour again.
struct EraserToggle: View {
    var model: LayoutWindowModel

    var body: some View {
        @Bindable var model = model
        Toggle(isOn: $model.isErasing) { Label("Eraser", systemImage: "eraser") }
            .toggleStyle(.button)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help(Text("Eraser: keys go back to the layer color"))
    }
}
