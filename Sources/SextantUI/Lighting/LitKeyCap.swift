import SextantDomain
import SwiftUI

/// How a key lights in the Lighting lens (spec §6.2): its own colour, its layer's colour, or off.
enum KeyLight: Equatable {
    case own(HexColor), layer(HexColor), off

    init(own: HexColor?, layer: HexColor?) {
        self = own.map(Self.own) ?? layer.map(Self.layer) ?? .off
    }

    /// The colour and its strength: light inherited from the layer shows at 35%, so painted keys pop.
    var tint: (color: HexColor, strength: Double)? {
        switch self {
        case let .own(color): (color, 1)
        case let .layer(color): (color, 0.35)
        case .off: nil
        }
    }

    var spoken: String {
        switch self {
        case let .own(color): String(localized: "Own color \(color.hex)")
        case let .layer(color): String(localized: "Layer color \(color.hex)")
        case .off: String(localized: "Off")
        }
    }
}

/// A cap in the Lighting lens: a backlit face (tint, rim, and a glow in dark mode), an unlit face with "off", and
/// the legend in ink picked by luminance (spec §6.2). Hovering shows a dashed ring in the brush colour; a live press
/// shrinks the cap and rings it in the live colour.
struct LitKeyCap: View {
    var model: KeyCapModel
    var light: KeyLight
    var u: CGFloat
    /// Live presses light in every lens (spec §2.2); read here so a press redraws only this cap.
    var press: PressedKeys.KeyState?
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.brush) private var brush

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 0.16 * u, style: .continuous)
        let tint = light.tint
        let isDown = press?.isDown ?? false
        ZStack {
            shape.fill(tint == nil ? Tokens.capUnlit.color : Tokens.capTop.color)
            if let tint { shape.fill(tint.color.color.opacity(0.4 * tint.strength)) }
            VStack(spacing: 0.02 * u) {
                if model.kind == .disabled {
                    Image(systemName: "nosign").font(.system(size: 0.24 * u)).opacity(0.5)
                } else if let primary = model.legend.legend.primary {
                    CapLegendView(action: primary, u: u, isLabel: model.kind == .label || model.kind == .macro)
                        .opacity(model.isGhost ? 0.4 : 1)
                }
                if tint == nil { Text("off").font(.system(size: 0.12 * u, weight: .medium)).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 0.06 * u)
        }
        .foregroundStyle(ink.primary, ink.secondary)
        .overlay {
            if let tint {
                shape.strokeBorder(LayerTones(tint.color).display.color.opacity(tint.strength), lineWidth: 2)
            } else {
                shape.strokeBorder(Tokens.capEdge.color, lineWidth: 0.75)
            }
        }
        .shadow(color: colorScheme == .dark ? tint.map { $0.color.color.opacity(0.6 * $0.strength) } ?? .clear : .clear, radius: 10)
        .overlay {
            if isHovered, let brush {
                shape.inset(by: -3).stroke(
                    brush.color?.color ?? Tokens.ghostStroke.color, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5]))
            }
        }
        .overlay {
            if isDown { shape.inset(by: -2).stroke((model.layerTones?.display ?? Tokens.success).color, lineWidth: 3) }
        }
        .scaleEffect(isDown && !reduceMotion ? 0.96 : 1)
        .animation(isDown ? nil : SextantMotion.keyRelease, value: isDown)
        .opacity(model.isDimmed ? 0.35 : 1)
        .onHover { isHovered = $0 }
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(KeyText.label(model.legend, index: model.index))
        .accessibilityValue(light.spoken)
    }

    /// Black or white by the lit face's luminance; the cap's own legend colours on an unlit face.
    private var ink: (primary: Color, secondary: Color) {
        guard let tint = light.tint else { return (Tokens.capLegend.color, Tokens.capLegend2.color) }
        let cap = colorScheme == .dark ? Tokens.capTop.dark : Tokens.capTop.light
        let a = 0.4 * tint.strength
        let c = tint.color
        let face = HexColor(
            red: cap.red + (c.red - cap.red) * a, green: cap.green + (c.green - cap.green) * a, blue: cap.blue + (c.blue - cap.blue) * a)
        // 0.179 is where black and white text have equal WCAG contrast.
        return face.luminance > 0.179 ? (.black, .black.opacity(0.6)) : (.white, .white.opacity(0.7))
    }
}
