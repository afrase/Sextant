import SextantDomain
import SwiftUI

/// What the board shows on caps (spec §4.9).
public enum LegendMode: String, CaseIterable, Sendable {
    /// Glyph legends with bands.
    case symbols
    /// The whole-key QMK expression.
    case qmk
    /// Key numbers.
    case index
}

/// Everything one cap needs to draw. `Equatable`, so a change elsewhere on the board doesn't redraw it.
struct KeyCapModel: Equatable {
    var index: Int
    var legend: ResolvedLegend
    /// Tones of the displayed layer, when it has a colour (rings, hatching).
    var layerTones: LayerTones?
    /// Tones of the layer a layer-tap hold activates (band ink).
    var holdTargetTones: LayerTones?
    var isSelected = false
    var mode: LegendMode = .symbols

    /// The key belongs to the displayed (non-base) layer, so it gets the layer ring.
    var isOwned: Bool { layerTones != nil && (!legend.isInherited || legend.activatesDisplayedLayer) }

    /// Short VoiceOver label (spec §4.11): "Return, hold for Sym+Num", "Z, inherited".
    var accessibilityLabel: String {
        let l = legend.legend
        var parts = [l.primary?.name ?? String(localized: "Key \(index)")]
        if l.secondarySlot == .hold, let hold = l.secondary { parts.append(String(localized: "hold for \(hold.layerName ?? hold.name)")) }
        if legend.isInherited { parts.append(String(localized: "inherited")) }
        return parts.joined(separator: ", ")
    }
}

/// One keycap, drawn upright at its cap size; the board rotates thumbs (spec §4.2–§4.7).
struct KeyCap: View, Equatable {
    var model: KeyCapModel
    /// Side of a 1u cap in points.
    var u: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    private var legend: KeyLegend { model.legend.legend }
    private var kind: KeyKind { model.legend.isInherited ? legend.kind : model.legend.ownKind }
    private var isGhost: Bool { model.legend.ownKind == .transparent }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 0.16 * u, style: .continuous) }

    var body: some View {
        ZStack {
            face
            content
                .opacity(isGhost ? 0.4 : 1)
                .padding(.horizontal, 0.06 * u)
            cornerMarks
        }
        .overlay { rings }
        .contentShape(shape)
    }

    // MARK: Face

    @ViewBuilder private var face: some View {
        if isGhost {
            shape.fill(Tokens.ghostFill.color)
                .overlay { shape.strokeBorder(Tokens.ghostStroke.color, style: StrokeStyle(lineWidth: 1, dash: [3, 2.5])) }
                .overlay {
                    if model.legend.activatesDisplayedLayer, let tones = model.layerTones { hatch(tones.display.color, opacity: 0.34) }
                }
        } else {
            shape
                .fill(LinearGradient(colors: [Tokens.capTop.color, Tokens.capBottom.color], startPoint: .top, endPoint: .bottom))
                .overlay { tint }
                .overlay { shape.strokeBorder(Tokens.capEdge.color, lineWidth: 0.75) }
                .overlay {
                    // Inner top-edge highlight.
                    shape.inset(by: 1).stroke(Tokens.capHighlight.color, lineWidth: 1)
                        .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.25)))
                }
                .shadow(color: .black.opacity(0.10), radius: 1, y: 1)
                .shadow(color: .black.opacity(0.06), radius: 3, y: 2)
                .overlay { if kind == .disabled { hatch(Tokens.kind(.disabled)?.tint.color ?? .gray, opacity: 0.12) } }
        }
    }

    /// Faint kind tint (≤ 5%) for single-function special kinds.
    @ViewBuilder private var tint: some View {
        if !hasBand, let k = Tokens.kind(kind) {
            shape.fill(k.tint.color.opacity(0.05))
        }
    }

    private func hatch(_ color: Color, opacity: Double) -> some View {
        Canvas { ctx, size in
            let step = max(3, 0.10 * u)
            var path = Path()
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += step
            }
            ctx.stroke(path, with: .color(color.opacity(opacity)), lineWidth: 1)
        }
        .clipShape(shape)
    }

    // MARK: Content

    /// A hold band shows what the hold does under the tap legend (dual-function keys).
    private var hasBand: Bool {
        model.mode == .symbols && legend.secondarySlot == .hold && legend.primarySlot == .tap && legend.secondary != nil
    }

    /// Hold-only keys (Main 18 ⌃, 25 ⌘) show a quiet "hold" marker in the band position.
    private var isHoldOnly: Bool { model.mode == .symbols && legend.primarySlot == .hold }

    @ViewBuilder private var content: some View {
        switch model.mode {
        case .qmk:
            Text(legend.qmk)
                .font(.system(size: 0.12 * u, design: .monospaced))
                .foregroundStyle(Tokens.capLegend.color)
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(.center)
        case .index:
            VStack(spacing: 0.02 * u) {
                Text(verbatim: "\(model.index)").font(.system(size: 0.30 * u, weight: .medium, design: .monospaced))
                if let p = legend.primary { Text(p.text).font(.system(size: 0.14 * u)).lineLimit(1) }
            }
            .foregroundStyle(Tokens.capLegend.color)
        case .symbols:
            VStack(spacing: 0) {
                primaryZone
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if hasBand, let hold = legend.secondary {
                    band(for: hold)
                        .frame(height: 0.30 * u)
                } else if isHoldOnly {
                    Text("hold")
                        .font(.system(size: 0.11 * u, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(height: 0.30 * u)
                }
            }
            .overlay(alignment: .bottom) { signalBar }
        }
    }

    @ViewBuilder private var primaryZone: some View {
        if let primary = legend.primary {
            VStack(spacing: 0.02 * u) {
                CapLegendView(action: primary, u: u, isLabel: kind == .label || kind == .macro)
                if let annotation = legend.annotation {
                    Text(annotation)
                        .font(.system(size: 0.13 * u, design: .monospaced))
                        .foregroundStyle(Tokens.capLegend2.color)
                        .lineLimit(1)
                }
            }
        }
    }

    private func band(for hold: ActionLegend) -> some View {
        let isLayer = hold.layer != nil
        let k = isLayer ? nil : (hold.modifiers.isEmpty && hold.side == nil ? Tokens.holdKey : Tokens.kind(.modifier))
        let fill = (k?.tint.color ?? model.holdTargetTones?.display.color ?? Tokens.layerKind.tint.color)
        let ink = isLayer ? (model.holdTargetTones?.ink.color ?? Tokens.layerKind.ink.color) : (k?.ink.color ?? Tokens.capLegend.color)
        return ZStack {
            Rectangle().fill(fill.opacity(colorScheme == .dark ? 0.18 : 0.12))
            HStack(spacing: 0.04 * u) {
                if isLayer {
                    Image(systemName: "square.stack.3d.up.fill").font(.system(size: 0.13 * u))
                    Text(hold.layerName ?? "").font(.system(size: 0.14 * u, weight: .semibold))
                } else if let side = hold.side, hold.text.count == 1 {
                    Text(hold.text).font(.system(size: 0.15 * u, weight: .semibold))
                    Text(side == .left ? "L" : "R").font(.system(size: 0.10 * u, weight: .bold)).opacity(0.7)
                } else {
                    Text(CapLegendView.capText(for: hold)).font(.system(size: 0.15 * u, weight: .semibold))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(ink)
            .padding(.horizontal, 0.06 * u)
        }
        .overlay(alignment: .top) { Rectangle().fill(fill.opacity(0.45)).frame(height: 0.5) }
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 0.16 * u, bottomTrailingRadius: 0.16 * u, style: .continuous))
        .padding(.horizontal, -0.06 * u)
    }

    @ViewBuilder private var signalBar: some View {
        // Reset (QK_BOOT) is a regular key with a red bar: it puts the keyboard in flash mode.
        let color = legend.qmk == "QK_BOOT" ? Tokens.danger.color : Tokens.kind(kind)?.tint.color
        if !hasBand, !isGhost, kind != .disabled, let color {
            Capsule()
                .fill(color)
                .frame(width: 0.36 * u, height: max(2, 0.05 * u))
                .padding(.bottom, 0.08 * u)
        }
    }

    // MARK: Corners and rings

    @ViewBuilder private var cornerMarks: some View {
        if let glow = legend.swatch, !isGhost, legend.slots.values.allSatisfy({ $0.color == nil }) {
            Circle()
                .fill(glow.color)
                .overlay { Circle().strokeBorder(Tokens.capEdge.color, lineWidth: 0.5) }
                .frame(width: 0.11 * u, height: 0.11 * u)
                .padding(0.09 * u)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
    }

    @ViewBuilder private var rings: some View {
        ZStack {
            if model.isOwned, let tones = model.layerTones {
                shape.inset(by: -1).stroke(tones.display.color, lineWidth: 1.25)
            }
            if model.isSelected {
                RoundedRectangle(cornerRadius: 0.16 * u + 2.5, style: .continuous)
                    .inset(by: -2.5)
                    .stroke(Color.accentColor, lineWidth: 2)
            }
        }
        .allowsHitTesting(false)
    }

    nonisolated static func == (a: Self, b: Self) -> Bool { a.model == b.model && a.u == b.u }
}

/// One action drawn as a cap legend: glyph, word, symbol with caption, swatch or label (spec §4.3).
struct CapLegendView: View {
    var action: ActionLegend
    var u: CGFloat
    var isLabel = false

    /// Words caps show instead of the catalog glyph (the ⎋ glyph is for menus and hints).
    static let words: [String: String] = [
        "KC_ESCAPE": "Esc", "KC_SPACE": "Space", "KC_HOME": "Home", "KC_END": "End", "KC_PGUP": "PgUp", "KC_PAGE_UP": "PgUp",
        "KC_PGDN": "PgDn", "KC_PAGE_DOWN": "PgDn", "KC_INSERT": "Ins", "KC_PSCR": "PrtSc", "KC_PRINT_SCREEN": "PrtSc",
        "QK_BOOT": "Reset",
    ]
    static let arrows: [String: String] = [
        "KC_LEFT": "arrow.left", "KC_RIGHT": "arrow.right", "KC_UP": "arrow.up", "KC_DOWN": "arrow.down",
    ]

    static func capText(for action: ActionLegend) -> String {
        words[KeycodeCatalog.canonicalCode(action.qmk)] ?? action.text
    }

    var body: some View {
        let code = KeycodeCatalog.canonicalCode(action.qmk)
        Group {
            if isLabel {
                // A custom label (or macro name) always shows as written, whatever the key does.
                text(action.text)
            } else if let swatch = action.color {
                VStack(spacing: 0.04 * u) {
                    Circle().fill(swatch.color)
                        .overlay { Circle().strokeBorder(.black.opacity(0.15), lineWidth: 0.5) }
                        .frame(width: 0.30 * u, height: 0.30 * u)
                        .shadow(color: swatch.color.opacity(0.6), radius: 0.08 * u)
                    caption(String(localized: "Colour"))
                }
            } else if let layer = action.layerName {
                VStack(spacing: 0.02 * u) {
                    Image(systemName: "square.stack.3d.up.fill").font(.system(size: 0.20 * u))
                    Text(layer).font(.system(size: 0.15 * u, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                }
                .foregroundStyle(Tokens.capLegend.color)
            } else if let arrow = Self.arrows[code] {
                Image(systemName: arrow).font(.system(size: 0.30 * u)).foregroundStyle(Tokens.capLegend.color)
            } else if let word = Self.words[code] {
                Text(word)
                    .font(.system(size: 0.22 * u, weight: .semibold))
                    .foregroundStyle(code == "QK_BOOT" ? Tokens.danger.color : Tokens.capLegend.color)
            } else if let symbol = action.symbol, [.media, .lighting, .mouse].contains(action.category) {
                VStack(spacing: 0.03 * u) {
                    Image(systemName: symbol).font(.system(size: 0.25 * u)).foregroundStyle(Tokens.capLegend.color)
                    caption(action.text)
                }
            } else if let side = action.side, action.text.count == 1 {
                HStack(alignment: .firstTextBaseline, spacing: 0.02 * u) {
                    Text(action.text).font(.system(size: 0.34 * u))
                    Text(side == .left ? "L" : "R").font(.system(size: 0.13 * u, weight: .bold)).opacity(0.7)
                        .baselineOffset(-0.04 * u)
                }
                .foregroundStyle(Tokens.capLegend.color)
            } else {
                text(action.text)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private func text(_ s: String) -> some View {
        let count = s.count
        if count == 1 && !isLabel {
            Text(s.uppercased()).font(.system(size: 0.36 * u, weight: .medium)).foregroundStyle(Tokens.capLegend.color)
        } else if count <= 4 && !isLabel {
            Text(s).font(.system(size: 0.24 * u, weight: .semibold)).foregroundStyle(Tokens.capLegend.color)
        } else {
            Text(s)
                .font(.system(size: 0.17 * u, weight: .semibold))
                .foregroundStyle(Tokens.capLegend.color)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.center)
        }
    }

    private func caption(_ s: String) -> some View {
        Text(s).font(.system(size: 0.13 * u, weight: .medium)).foregroundStyle(Tokens.capLegend2.color).lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}
