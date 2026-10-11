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

    /// Menu title (View ▸ Legends).
    var title: String {
        switch self {
        case .symbols: String(localized: "Symbols")
        case .qmk: String(localized: "QMK Codes")
        case .index: String(localized: "Key Numbers")
        }
    }
}

/// Everything one cap needs to draw. `Equatable`, so a change elsewhere on the board doesn't redraw it.
struct KeyCapModel: Equatable {
    var index: Int
    var legend: ResolvedLegend
    /// Tones of the displayed layer, when it has a colour (rings, hatching, pressed fill).
    var layerTones: LayerTones?
    /// Tones of the layer this key's layer action targets (layer-key bar, layer-hold band).
    var targetTones: LayerTones?
    var mode: LegendMode
    var issue: LayoutIssue.Severity?
    /// The key's own LED colour on this layer, even when it is transparent (spec §4.8 LED dot).
    var ownGlow: HexColor?
    /// Dimmed while the kind key points at another kind (spec §3.7).
    var isDimmed = false

    init(layout: KeyboardLayout, layer: Int, index: Int, mode: LegendMode = .symbols, issue: LayoutIssue.Severity? = nil) {
        let legend = Legends.legend(layout: layout, layer: layer, index: index)
        let target = legend.legend.secondarySlot == .hold ? legend.legend.secondary?.layer : legend.legend.primary?.layer
        self.index = index
        self.legend = legend
        layerTones = layer > 0 ? layout.layers[safe: layer]?.color.map(LayerTones.init) : nil
        targetTones = target.flatMap { layout.layers[safe: $0]?.color }.map(LayerTones.init)
        self.mode = mode
        self.issue = issue
        ownGlow = layout.key(layer: layer, index: index)?.glowColor
    }

    /// Transparent on this layer: drawn as a ghost with the inherited legend.
    var isGhost: Bool { legend.ownKind == .transparent }
    /// The kind drawn: a transparent key shows the kind it inherits.
    var kind: KeyKind { legend.isInherited ? legend.legend.kind : legend.ownKind }
    /// The layer ring goes on keys the displayed layer owns, and on the key that holds it (spec §4.5).
    var isOwned: Bool { layerTones != nil && (!isGhost || legend.activatesDisplayedLayer) }

    /// What the hold band shows: a dual-function key's hold, or a tap dance's hold or double tap (spec §4.4).
    var band: (action: ActionLegend, slot: KeySlot)? {
        let l = legend.legend
        guard mode == .symbols, l.primarySlot == .tap, let slot = l.secondarySlot, let action = l.secondary else { return nil }
        return slot == .hold || kind == .tapDance ? (action, slot) : nil
    }

    /// Hold-only keys (Main 18 ⌃, 25 ⌘) show a quiet "hold" marker in the band position. A layer key's caption
    /// already says it.
    var isHoldOnly: Bool { mode == .symbols && legend.legend.primarySlot == .hold && legend.legend.primary?.layer == nil }

    /// The signal-bar colour, for single-function special kinds and tap dances (spec §4.4). Reset is red.
    var bar: Token? {
        guard mode == .symbols, !isGhost, kind != .disabled, band == nil || kind == .tapDance else { return nil }
        if legend.legend.qmk == "QK_BOOT" { return Tokens.danger }
        if kind == .layer { return targetTones?.display ?? Tokens.layerKind.tint }
        return Tokens.kind(kind)?.tint
    }
}

/// One keycap, drawn upright at its cap size; the board rotates thumbs (spec §4.2–§4.8).
struct KeyCap: View, Equatable {
    var model: KeyCapModel
    /// Side of a 1u cap in points.
    var u: CGFloat
    /// Cap height in points; the tall inner thumb is taller than `u`.
    var height: CGFloat?
    var isPressed = false
    var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var legend: KeyLegend { model.legend.legend }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 0.16 * u, style: .continuous) }
    private var isDark: Bool { colorScheme == .dark }
    private var highContrast: Bool { contrast == .increased }
    /// Band height: 30% of the cap, 26% on the tall thumb.
    private var bandHeight: CGFloat {
        let h = height ?? u
        return h * (h > 1.2 * u ? 0.26 : 0.30)
    }

    var body: some View {
        ZStack {
            face
            if isPressed { pressedFill }
            content
                .opacity(model.isGhost ? 0.4 : 1)
                .padding(.horizontal, 0.06 * u)
            corners
        }
        .foregroundStyle(ink.primary, ink.secondary)
        .overlay { rings }
        .scaleEffect(isPressed && !reduceMotion ? 0.96 : 1)
        .animation(isPressed ? nil : SextantMotion.keyRelease, value: isPressed)
        .opacity(model.isDimmed ? 0.35 : 1)
        .contentShape(shape)
    }

    nonisolated static func == (a: Self, b: Self) -> Bool {
        a.model == b.model && a.u == b.u && a.height == b.height && a.isPressed == b.isPressed && a.isHovered == b.isHovered
    }

    // MARK: Face

    @ViewBuilder private var face: some View {
        if model.isGhost {
            shape.fill(Tokens.ghostFill.color)
                .overlay { shape.strokeBorder(Tokens.ghostStroke.color, style: StrokeStyle(lineWidth: 1, dash: [3, 2.5])) }
                .overlay {
                    if model.legend.activatesDisplayedLayer, let tones = model.layerTones {
                        Hatch(color: tones.display.color.opacity(isDark ? 0.38 : 0.30), spacing: 0.10 * u).clipShape(shape)
                    }
                }
        } else {
            shape
                .fill(LinearGradient(colors: [Tokens.capTop.color, Tokens.capBottom.color], startPoint: .top, endPoint: .bottom))
                .overlay { if let bar = model.bar { shape.fill(bar.color.opacity(0.05)) } }
                .overlay {
                    if model.kind == .disabled, let disabled = Tokens.kind(.disabled) {
                        Hatch(color: disabled.tint.color.opacity(0.12), spacing: 0.10 * u).clipShape(shape)
                    }
                }
                .overlay { shape.strokeBorder(Tokens.capEdge.color, lineWidth: 0.75) }
                .overlay {
                    // Inner top-edge highlight.
                    shape.inset(by: 1).stroke(Tokens.capHighlight.color, lineWidth: 1)
                        .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.25)))
                }
                .shadow(color: .black.opacity(isDark ? 0.45 : 0.10), radius: isDark ? 2.5 : 1, y: isDark ? 2 : 1)
                .shadow(color: .black.opacity(isDark ? 0 : 0.06), radius: 3, y: 2)
        }
    }

    /// Opacity of the pressed fill; the pressed ink's contrast math mixes with the same value.
    private var pressedAlpha: Double { isDark ? 0.8 : 0.65 }

    /// Live press: the face fills with the layer colour (live green on the base layer), spec §4.7.
    private var pressedFill: some View {
        let tone = model.layerTones?.display ?? Tokens.success
        return shape.fill(tone.color.opacity(pressedAlpha))
            .shadow(color: isDark ? tone.color.opacity(0.6) : .clear, radius: 0.18 * u)
    }

    /// Legend ink: the cap tokens, or black / white by luminance on a pressed face.
    private var ink: (primary: Color, secondary: Color) {
        guard isPressed else { return (Tokens.capLegend.color, Tokens.capLegend2.color) }
        let tone = model.layerTones?.display ?? Tokens.success
        let (fill, cap) = isDark ? (tone.dark, Tokens.capTop.dark) : (tone.light, Tokens.capTop.light)
        let alpha = pressedAlpha
        let mixed = HexColor(
            red: cap.red + (fill.red - cap.red) * alpha, green: cap.green + (fill.green - cap.green) * alpha,
            blue: cap.blue + (fill.blue - cap.blue) * alpha)
        // 0.179 is where black and white text have equal WCAG contrast.
        return mixed.luminance > 0.179 ? (.black, .black.opacity(0.7)) : (.white, .white.opacity(0.75))
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch model.mode {
        case .qmk:
            Text(legend.qmk)
                .font(.system(size: 0.12 * u, design: .monospaced))
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(.center)
        case .index:
            VStack(spacing: 0.02 * u) {
                Text(verbatim: "\(model.index)").font(.system(size: 0.30 * u, weight: .medium, design: .monospaced))
                if let p = legend.primary { Text(p.text).font(.system(size: 0.14 * u)).lineLimit(1).foregroundStyle(.secondary) }
            }
        case .symbols:
            VStack(spacing: 0) {
                primaryZone
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let band = model.band {
                    bandView(band).frame(height: bandHeight)
                } else if model.isHoldOnly {
                    // Top of the band zone, so it clears the signal bar below it.
                    Text("hold")
                        .font(.system(size: 0.11 * u, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(height: bandHeight, alignment: .top)
                }
            }
            .overlay(alignment: .bottom) { signalBar }
        }
    }

    @ViewBuilder private var primaryZone: some View {
        if model.kind == .disabled {
            Image(systemName: "nosign").font(.system(size: 0.24 * u)).opacity(0.5)
        } else if let primary = legend.primary {
            VStack(spacing: 0.02 * u) {
                CapLegendView(action: primary, u: u, isLabel: model.kind == .label || model.kind == .macro)
                if let annotation = legend.annotation {
                    Text(annotation)
                        .font(.system(size: 0.13 * u, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
    }

    private func bandView(_ band: (action: ActionLegend, slot: KeySlot)) -> some View {
        let hold = band.action
        let isLayer = hold.layer != nil
        let isTapDanceBand = model.kind == .tapDance && band.slot != .hold
        let tokens =
            isTapDanceBand
            ? Tokens.kind(.tapDance)
            : isLayer ? nil : (hold.modifiers.isEmpty && hold.side == nil ? Tokens.holdKey : Tokens.kind(.modifier))
        let fill = tokens?.tint.color ?? model.targetTones?.display.color ?? Tokens.layerKind.tint.color
        let ink = tokens?.ink.color ?? model.targetTones?.ink.color ?? Tokens.layerKind.ink.color
        let prefix = band.slot == .doubleTap ? "2× " : ""
        return ZStack {
            Rectangle().fill(fill.opacity(isDark ? 0.18 : 0.12))
            HStack(spacing: 0.04 * u) {
                if isLayer {
                    Image(systemName: "square.stack.3d.up.fill").font(.system(size: 0.13 * u))
                    Text(prefix + (hold.layerName ?? "")).font(.system(size: 0.14 * u, weight: .semibold))
                } else if let side = hold.side, hold.text.count == 1 {
                    Text(prefix + hold.text).font(.system(size: 0.15 * u, weight: .semibold))
                    Text(side == .left ? "L" : "R").font(.system(size: 0.10 * u, weight: .bold)).opacity(0.7)
                } else {
                    Text(prefix + CapLegendView.capText(for: hold)).font(.system(size: 0.15 * u, weight: .semibold))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(ink)
            .padding(.horizontal, 0.06 * u)
            // A tap dance also draws its bar inside the band; lift the text clear of it.
            .padding(.bottom, model.bar == nil ? 0 : 0.07 * u)
        }
        .overlay(alignment: .top) { Rectangle().fill(fill.opacity(0.45)).frame(height: 0.5) }
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 0.16 * u, bottomTrailingRadius: 0.16 * u, style: .continuous))
        .padding(.horizontal, -0.06 * u)
    }

    @ViewBuilder private var signalBar: some View {
        if let bar = model.bar {
            Capsule()
                .fill(bar.color)
                .overlay { if highContrast { Capsule().strokeBorder(.black.opacity(0.5), lineWidth: 0.5) } }
                .frame(width: 0.36 * u, height: max(2, 0.05 * u) + (highContrast ? 1 : 0))
                .padding(.bottom, model.band == nil ? 0.08 * u : 0.04 * u)
        }
    }

    // MARK: Corners and rings

    /// Top right: issue > unknown code > LED dot (spec §4.8). Bottom right: the Differentiate Without Color glyph (§11).
    private var corners: some View {
        ZStack(alignment: .topTrailing) {
            if let issue = model.issue {
                badge(issue == .error ? Tokens.danger : Tokens.warning)
            } else if legend.primary?.isUnknown == true, !model.isGhost {
                badge(Tokens.warning)
            } else if let glow = model.ownGlow {
                Circle()
                    .fill(glow.color)
                    .overlay { Circle().strokeBorder(Tokens.capEdge.color, lineWidth: 0.5) }
                    .frame(width: 0.11 * u, height: 0.11 * u)
                    .padding(0.09 * u)
            }
            if differentiateWithoutColor, !model.isGhost, model.mode == .symbols {
                kindGlyph
                    .font(.system(size: 0.12 * u, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(0.07 * u)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    private func badge(_ token: Token) -> some View {
        Circle().fill(token.color)
            .overlay { Text(verbatim: "!").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white) }
            .frame(width: 14, height: 14)
            .offset(x: 4, y: -4)
    }

    @ViewBuilder private var kindGlyph: some View {
        switch model.kind {
        case .modifier: Text(verbatim: "⌘")
        case .layer: Image(systemName: "square.stack.3d.up.fill")
        case .lighting: Image(systemName: "lightbulb")
        case .label: Text(verbatim: "Aa")
        case .macro: Image(systemName: "list.bullet")
        case .tapDance: Text(verbatim: "2×")
        case .regular, .dualFunction, .transparent, .disabled: EmptyView()
        }
    }

    private var rings: some View {
        ZStack {
            if let issue = model.issue {
                shape.inset(by: -2).stroke((issue == .error ? Tokens.danger : Tokens.warning).color, lineWidth: 2)
            } else if model.isOwned, let tones = model.layerTones {
                let width: CGFloat = highContrast ? 2 : isDark ? 1.25 : 1.5
                let dashed = differentiateWithoutColor && model.legend.activatesDisplayedLayer
                shape.inset(by: -1)
                    .stroke(tones.display.color, style: StrokeStyle(lineWidth: width, dash: dashed ? [3, 2] : []))
                    .shadow(color: isDark ? tones.display.color.opacity(0.45) : .clear, radius: 3)
            }
            if isHovered {
                shape.strokeBorder(Color.primary.opacity(highContrast ? 0.4 : 0.22), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
}

/// 45° hatching (disabled keys, and the key holding the displayed layer).
private struct Hatch: View {
    var color: Color
    var spacing: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let step = max(3, spacing)
            var path = Path()
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += step
            }
            ctx.stroke(path, with: .color(color), lineWidth: 1)
        }
    }
}

/// One action drawn as a cap legend: glyph, word, symbol with caption, swatch or label (spec §4.3). Ink comes
/// from the cap's foreground style, so a pressed key can flip it.
struct CapLegendView: View {
    var action: ActionLegend
    var u: CGFloat
    var isLabel = false

    /// Words caps show instead of the catalog glyph (the ⎋ glyph is for menus and hints).
    nonisolated static let words: [String: String] = [
        "KC_ESCAPE": "Esc", "KC_SPACE": "Space", "KC_HOME": "Home", "KC_END": "End", "KC_PGUP": "PgUp", "KC_PAGE_UP": "PgUp",
        "KC_PGDN": "PgDn", "KC_PAGE_DOWN": "PgDn", "KC_INSERT": "Ins", "KC_PSCR": "PrtSc", "KC_PRINT_SCREEN": "PrtSc",
        "QK_BOOT": "Reset",
    ]
    nonisolated static let arrows: [String: String] = [
        "KC_LEFT": "arrow.left", "KC_RIGHT": "arrow.right", "KC_UP": "arrow.up", "KC_DOWN": "arrow.down",
    ]

    nonisolated static func capText(for action: ActionLegend) -> String {
        words[KeycodeCatalog.canonicalCode(action.qmk)] ?? action.text
    }

    /// The caption under a layer key's name (spec §5.3): what the key does to the layer.
    nonisolated static func layerCaption(_ qmk: String) -> String? {
        switch qmk.prefix(while: { $0 != "(" }) {
        case "MO", "LM": String(localized: "hold")
        case "TG": String(localized: "toggle")
        case "TO": String(localized: "go to")
        case "TT": String(localized: "tap-toggle")
        case "OSL": String(localized: "one-shot")
        default: nil
        }
    }

    var body: some View {
        legend(KeycodeCatalog.canonicalCode(action.qmk)).accessibilityHidden(true)
    }

    @ViewBuilder private func legend(_ code: String) -> some View {
        if isLabel {
            // A custom label (or macro name) always shows as written, whatever the key does.
            text(action.text)
        } else if action.isUnknown {
            // Unknown codes show as stored, in mono (the cap adds a warning badge).
            Text(action.qmk)
                .font(.system(size: 0.13 * u, design: .monospaced))
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(.center)
        } else if let swatch = action.color {
            VStack(spacing: 0.04 * u) {
                Circle().fill(swatch.color)
                    .overlay { Circle().strokeBorder(.black.opacity(0.15), lineWidth: 0.5) }
                    .frame(width: 0.30 * u, height: 0.30 * u)
                    .shadow(color: swatch.color.opacity(0.7), radius: 0.08 * u)
                caption(String(localized: "Color"))
            }
        } else if let layer = action.layerName {
            VStack(spacing: 0.02 * u) {
                Image(systemName: "square.stack.3d.up.fill").font(.system(size: 0.18 * u))
                Text(layer).font(.system(size: 0.15 * u, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                if let verb = Self.layerCaption(action.qmk) { caption(verb) }
            }
        } else if let arrow = Self.arrows[code] {
            Image(systemName: arrow).font(.system(size: 0.30 * u))
        } else if let word = Self.words[code] {
            Text(word)
                .font(.system(size: 0.22 * u, weight: .semibold))
                .foregroundStyle(code == "QK_BOOT" ? AnyShapeStyle(Tokens.danger.color) : AnyShapeStyle(.foreground))
        } else if let symbol = action.symbol, [.media, .lighting, .mouse].contains(action.category) {
            VStack(spacing: 0.03 * u) {
                Image(systemName: symbol).font(.system(size: 0.25 * u))
                caption(action.text)
            }
        } else if let side = action.side, action.text.count == 1 {
            HStack(alignment: .firstTextBaseline, spacing: 0.02 * u) {
                Text(action.text).font(.system(size: 0.34 * u))
                Text(side == .left ? "L" : "R").font(.system(size: 0.13 * u, weight: .bold)).opacity(0.7)
                    .baselineOffset(-0.04 * u)
            }
        } else {
            text(action.text)
        }
    }

    @ViewBuilder private func text(_ s: String) -> some View {
        let count = s.count
        if count == 1 && !isLabel {
            Text(s.uppercased()).font(.system(size: 0.36 * u, weight: .medium))
        } else if count <= 4 && !isLabel {
            Text(s).font(.system(size: 0.22 * u, weight: .semibold))
        } else {
            Text(s)
                .font(.system(size: 0.17 * u, weight: .semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.center)
        }
    }

    private func caption(_ s: String) -> some View {
        Text(s).font(.system(size: 0.13 * u, weight: .medium)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
    }
}
