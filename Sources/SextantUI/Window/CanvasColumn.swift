import SextantApplication
import SextantDomain
import SwiftUI

/// Whether the bench draws its precision grid (View ▸ Show Grid Behind Keyboard; spec §4.10).
enum BenchGrid {
    static let key = "showsBenchGrid"
}

/// The centre column's fixed bands (spec §3.3). Only the board area flexes, so the board never moves when the
/// selection, lens, lane or strip change.
struct CanvasColumn: View {
    var model: LayoutWindowModel
    var session: EditSession
    @AppStorage(BenchGrid.key) private var showsGrid = true

    var body: some View {
        VStack(spacing: 0) {
            CanvasHeader(model: model, session: session).frame(height: 44)
            LensLane(model: model).frame(height: 36)
            BoardView(
                session: session, mode: model.legendMode, issues: model.issueMap, pressed: model.pressedKeys,
                highlightedKind: model.highlightedKind, showsGrid: showsGrid)
            ContextStrip(model: model, session: session).frame(height: 76)
            BoardFooter(model: model).frame(height: 32)
        }
        .background(Bench())
    }
}

/// Layer jump menu and readout (leading), lens control (trailing).
private struct CanvasHeader: View {
    var model: LayoutWindowModel
    var session: EditSession

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 12) {
            Menu {
                ForEach(Array(session.layout.layers.enumerated()), id: \.element.id) { index, layer in
                    Toggle(
                        String(localized: "\(index) · \(layer.title)"),
                        isOn: Binding(get: { session.selection.layer == index }, set: { _ in session.select(layer: index) }))
                }
            } label: {
                HStack(spacing: 6) {
                    LayerChip(color: session.currentLayer?.color, size: 10)
                    Text(session.currentLayer?.title ?? "").fontWeight(.medium)
                }
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
            .accessibilityLabel(String(localized: "Layer: \(session.currentLayer?.title ?? "")"))
            Text(model.readout)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Picker("Lens", selection: $model.lens) {
                ForEach(Lens.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
        }
        .padding(.horizontal, 20)
    }
}

/// Up to two glass capsules, centred (spec §3.7). Today: the status capsule (an issue, else live Follow).
private struct LensLane: View {
    var model: LayoutWindowModel
    @Environment(\.motion) private var motion

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                if let status = model.laneStatus {
                    capsule(status)
                        .glassEffectTransition(.materialize)
                }
            }
        }
        .animation(motion.standard, value: model.laneStatus)
    }

    @ViewBuilder private func capsule(_ status: LaneStatus) -> some View {
        HStack(spacing: 8) {
            switch status {
            case let .issue(text, key):
                Image(systemName: "xmark.octagon.fill").foregroundStyle(Tokens.danger.color)
                Text(text).lineLimit(1)
                Button("Show Key") { model.showIssue(key) }.buttonStyle(.borderless)
            case let .live(text):
                Circle().fill(Tokens.success.color).frame(width: 7, height: 7)
                Text(text).lineLimit(1)
                Button("Stop Following") { model.isFollowing = false }.buttonStyle(.borderless)
            }
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 12)
        .frame(height: 28)
        .surface(Capsule(), interactive: true)
    }
}

/// The selected key on every layer, lens information, or the hint (spec §3.7). Always 76 pt tall.
private struct ContextStrip: View {
    var model: LayoutWindowModel
    var session: EditSession

    var body: some View {
        switch model.lens {
        case .keys:
            if let key = session.selection.keyIndex {
                cards { index, layer in keyCard(layer: index, key: key, title: layer.title) }
            } else {
                // shortcut: the spec's " · ⏎ edits · ⌘K finds anything" joins when the picker and palette exist (step 5).
                Text("Select a key to see it on every layer")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 20)
            }
        case .lighting:
            cards { index, layer in lightingCard(layer: index, item: layer) }
        }
    }

    /// One card per layer from layer 0 up, scrolling sideways when they don't fit.
    private func cards(@ViewBuilder _ card: @escaping (Int, Layer) -> some View) -> some View {
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
                    Text(String(localized: "\(own) of \(item.keys.count) keys have their own colour"))
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

/// The kind key (leading) and the legend switch (trailing), spec §3.7.
private struct BoardFooter: View {
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
                        .onLongPressGesture(minimumDuration: 0, perform: {}, onPressingChanged: { model.highlightedKind = $0 ? kind : nil })
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .scrollIndicators(.never)
            GlassEffectContainer(spacing: 8) {
                Picker("Legends", selection: $model.legendMode) {
                    Text(verbatim: "Aa").tag(LegendMode.symbols).accessibilityLabel(LegendMode.symbols.title)
                    Text(verbatim: "KC").tag(LegendMode.qmk).accessibilityLabel(LegendMode.qmk.title)
                    Text(verbatim: "#").tag(LegendMode.index).accessibilityLabel(LegendMode.index.title)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
                .padding(2)
                .surface(Capsule(), interactive: true)
                .help(Text("Legends: symbols, QMK codes (⌥⌘C) or key numbers (⌥⌘N)"))
            }
        }
        .padding(.horizontal, 20)
    }
}

/// A kind's mini cap swatch for the kind key: the same channels the board uses (spec §4.4).
private struct KindSwatch: View {
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
