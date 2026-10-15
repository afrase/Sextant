import SextantDomain
import SwiftUI

/// The kind key (leading) and the legend switch (trailing), spec §3.7.
struct BoardFooter: View {
    var model: LayoutWindowModel

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 12) {
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(model.kindsOnLayer, id: \.self) { kind in
                        HStack(spacing: 5) {
                            KindSwatch(kind: kind)
                            Text(kind.title).font(.caption).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        // Hovering or pressing a kind dims every other key (spec §3.7).
                        .onHover { model.highlightedKind = $0 ? kind : nil }
                        .onLongPressGesture(minimumDuration: 0, perform: {}, onPressingChanged: { if $0 { model.highlightedKind = kind } })
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .scrollIndicators(.never)
            // A kind can vanish under the pointer (another layer has none) without a hover exit.
            .onChange(of: model.kindsOnLayer) { model.highlightedKind = nil }
            // Bare, like the lens switch: a glass capsule around the control's own rounded track wasn't concentric.
            Picker("Legends", selection: $model.legendMode) {
                Text(verbatim: "Aa").tag(LegendMode.symbols).accessibilityLabel(LegendMode.symbols.title)
                Text(verbatim: "KC").tag(LegendMode.qmk).accessibilityLabel(LegendMode.qmk.title)
                Text(verbatim: "#").tag(LegendMode.index).accessibilityLabel(LegendMode.index.title)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .help(Text("Legends: symbols, QMK codes (⌥⌘C) or key numbers (⌥⌘N)"))
        }
        .padding(.horizontal, 20)
    }
}

/// A kind's mini cap swatch for the kind key: the same channels the board uses (spec §4.4).
struct KindSwatch: View {
    var kind: KeyKind

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        ZStack(alignment: .bottom) {
            if kind == .transparent {
                shape.fill(Tokens.ghostFill.color)
                    .overlay { shape.strokeBorder(Tokens.ghostStroke.color, style: StrokeStyle(lineWidth: 1, dash: [2, 1.5])) }
            } else {
                shape.fill(Tokens.capTop.color).overlay { shape.strokeBorder(Tokens.capEdge.color, lineWidth: 0.5) }
                if kind == .dualFunction, let mod = Tokens.kind(.modifier) {
                    Rectangle().fill(mod.tint.color.opacity(0.3)).frame(height: 5).clipShape(shape)
                } else if kind == .disabled {
                    Image(systemName: "nosign").font(.system(size: 8)).foregroundStyle(.secondary).frame(maxHeight: .infinity)
                } else if let bar = Tokens.kind(kind) {
                    Capsule().fill(bar.tint.color).frame(width: 7, height: 2).padding(.bottom, 2)
                }
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }
}
