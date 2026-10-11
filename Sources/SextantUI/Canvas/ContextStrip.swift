import SextantApplication
import SextantDomain
import SwiftUI

/// The selected key on every layer, lens information, or the hint (spec §3.7). Always 76 pt tall.
struct ContextStrip: View {
    var model: LayoutWindowModel
    var session: EditSession

    var body: some View {
        switch model.lens {
        case .keys:
            if let key = session.selection.keyIndex {
                cards { index, layer in keyCard(layer: index, key: key, title: layer.title) }
            } else {
                Text("Select a key to see it on every layer · ⏎ edits · ⌘K finds anything")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 20)
            }
        case .lighting:
            cards { index, layer in lightingCard(layer: index, item: layer) }
        }
    }

    /// One card per layer from layer 0 up, scrolling sideways when they don't fit, with the current layer's in view.
    private func cards(@ViewBuilder _ card: @escaping (Int, Layer) -> some View) -> some View {
        let current = session.currentLayer?.id
        return ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(Array(session.layout.layers.enumerated()), id: \.element.id) { index, layer in
                        card(index, layer)
                    }
                }
                .padding(.horizontal, 20)
                .frame(maxHeight: .infinity)
            }
            .scrollIndicators(.never)
            .onAppear { if let current { proxy.scrollTo(current, anchor: .center) } }
            .onChange(of: current) { if let current { proxy.scrollTo(current, anchor: .center) } }
        }
    }

    @ViewBuilder private func keyCard(layer: Int, key: Int, title: String) -> some View {
        let resolved = Legends.legend(layout: session.layout, layer: layer, index: key)
        let line = KeyText.stripLine(resolved)
        let transparent = resolved.ownKind == .transparent
        if layer > 0 {
            // Transparent keys fall through to the layer below.
            Image(systemName: "arrow.left")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .opacity(transparent ? 1 : 0)
                .accessibilityHidden(true)
        }
        Button {
            session.select(layer: layer)
        } label: {
            HStack(spacing: 8) {
                KeyCap(model: KeyCapModel(layout: session.layout, layer: layer, index: key), u: 36).frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        LayerChip(color: session.layout.layers[safe: layer]?.color, size: 8)
                        Text(title).font(.callout.weight(.medium)).lineLimit(1)
                    }
                    Text(line.text).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .frame(minWidth: 150, maxHeight: 60, alignment: .leading)
            .background(card(dashed: transparent, current: layer == session.selection.layer))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "\(title): \(line.spoken)"))
        .accessibilityAddTraits(layer == session.selection.layer ? .isSelected : [])
    }

    private func lightingCard(layer: Int, item: Layer) -> some View {
        let own = item.keys.filter { $0.glowColor != nil }.count
        return Button {
            session.select(layer: layer)
        } label: {
            HStack(spacing: 8) {
                LayerChip(color: item.color, size: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.callout.weight(.medium)).lineLimit(1)
                    Text(String(localized: "\(own) of \(item.keys.count) keys have their own color"))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .frame(minWidth: 150, maxHeight: 60, alignment: .leading)
            .background(card(dashed: false, current: layer == session.selection.layer))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(layer == session.selection.layer ? .isSelected : [])
    }

    private func card(dashed: Bool, current: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return shape.fill(dashed ? Tokens.ghostFill.color : Tokens.capTop.color.opacity(0.6))
            .overlay {
                if current {
                    shape.strokeBorder(Color.accentColor, lineWidth: 1.5)
                } else if dashed {
                    shape.strokeBorder(Tokens.ghostStroke.color, style: StrokeStyle(lineWidth: 1, dash: [3, 2.5]))
                } else {
                    shape.strokeBorder(Tokens.capEdge.color, lineWidth: 0.5)
                }
            }
    }
}
