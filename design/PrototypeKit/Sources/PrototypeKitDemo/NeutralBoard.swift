import SwiftUI
import PrototypeKit

/// A deliberately plain board render (system colours only) to verify geometry and legends.
/// Not a design direction.
struct NeutralBoard: View {
    var layout: KeyboardLayout = Samples.layout
    var layer: Int = 0
    var keySize: CGFloat = 58
    var pressed: Set<Int> = []
    var selected: Int? = nil
    var showIndices = false

    var body: some View {
        let geo = BoardGeometry.voyager.layout(keySize: keySize, spacingRatio: 0.1, padding: 14)
        ZStack(alignment: .topLeading) {
            if let nav = geo.navigator {
                Circle()
                    .strokeBorder(.tertiary, lineWidth: 1)
                    .frame(width: nav.diameter, height: nav.diameter)
                    .position(nav.center)
            }
            BoardCanvas(layout: geo) { frame in
                NeutralKey(legend: Legends.legend(layout: layout, layer: layer, index: frame.index),
                           layerColor: layer > 0 ? layout.layers[layer].color : nil,
                           isPressed: pressed.contains(frame.index), isSelected: selected == frame.index,
                           index: showIndices ? frame.index : nil)
            }
        }
        .frame(width: geo.size.width, height: geo.size.height)
    }
}

struct NeutralKey: View {
    var legend: ResolvedLegend
    var layerColor: HexColor?
    var isPressed = false
    var isSelected = false
    var index: Int?

    var body: some View {
        let l = legend.legend
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isPressed ? AnyShapeStyle(.tint.opacity(0.35)) : AnyShapeStyle(.background))
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary.opacity(0.6)), lineWidth: isSelected ? 2 : 1)
            if let c = layerColor, !legend.isInherited {
                RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(c.color.opacity(0.9), lineWidth: 1.5)
            }
            if legend.activatesDisplayedLayer {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.secondary.opacity(0.12))
            }
            VStack(spacing: 1) {
                primary(l)
                if let s = l.secondary {
                    HStack(spacing: 1) {
                        Text(s.text).font(.system(size: 10, weight: .medium))
                        if let side = s.side { Text(side == .left ? "L" : "R").font(.system(size: 6, weight: .semibold)).baselineOffset(-3) }
                    }
                    .foregroundStyle(.secondary)
                } else if let a = l.annotation {
                    Text(a).font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }
            .opacity(legend.isInherited ? 0.38 : 1)
            .padding(3)
            if let swatch = l.swatch, l.primary?.color != nil {
                Circle().fill(swatch.color).frame(width: 7, height: 7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(5)
            }
            if let index {
                Text("\(index)").font(.system(size: 7)).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(3)
            }
        }
    }

    @ViewBuilder
    func primary(_ l: KeyLegend) -> some View {
        if let p = l.primary {
            let isWord = p.text.count > 2
            HStack(spacing: 1) {
                if p.text.isEmpty, let sym = p.symbol {
                    Image(systemName: sym).font(.system(size: 15))
                } else if l.kind == .ledControl || (p.category == .media) || p.category == .navigator, let sym = p.symbol {
                    Image(systemName: sym).font(.system(size: 15))
                } else {
                    Text(p.text)
                        .font(.system(size: isWord ? 11 : 17, weight: .regular))
                        .lineLimit(2).minimumScaleFactor(0.6).multilineTextAlignment(.center)
                }
                if let side = p.side { Text(side == .left ? "L" : "R").font(.system(size: 7, weight: .semibold)).baselineOffset(-5) }
            }
        } else {
            Text(" ")
        }
    }
}
