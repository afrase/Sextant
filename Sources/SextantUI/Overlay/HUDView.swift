import SextantApplication
import SextantDomain
import SwiftUI

/// The overlay HUD (spec §8.4): a header with the layer's index tile, name, what holds it and the status lights, over
/// the layer's map with the keys held down lit. The panel's glass sits behind it, optionally tinted with the layer color
/// at 20%; an opaque dark panel under Reduce Transparency and Increase Contrast.
public struct HUDView: View {
    var layout: KeyboardLayout
    var layer: Int
    /// The key holding the layer on, on the layer it went down on; nil when the layer is locked.
    var holder: KeyRef?
    var pressed: Set<Int>
    var width: CGFloat
    var tints: Bool
    /// Settings › Keyboard's preview (ADR 0062): the header says "Preview" in place of held or locked.
    var isPreview: Bool

    public init(
        layout: KeyboardLayout, layer: Int, holder: KeyRef?, pressed: Set<Int>, width: CGFloat, tints: Bool = false,
        isPreview: Bool = false
    ) {
        self.layout = layout
        self.layer = layer
        self.holder = holder
        self.pressed = pressed
        self.width = width
        self.tints = tints
        self.isPreview = isPreview
    }

    static let cornerRadius: CGFloat = 24
    static let padding: CGFloat = 20
    static let headerHeight: CGFloat = 24
    static let spacing: CGFloat = 14

    /// The HUD's width on a screen `screenWidth` wide: the smaller of 720 pt and 46% of the screen at Medium, three
    /// quarters of that at Small and five quarters at Large, never closer than 16 pt to the screen's edges.
    static func width(size: OverlaySize, screenWidth: CGFloat) -> CGFloat {
        let scale: CGFloat =
            switch size {
            case .small: 0.75
            case .medium: 1
            case .large: 1.25
            }
        return min((min(720, screenWidth * 0.46) * scale).rounded(), screenWidth - 32)
    }

    /// The HUD's height at `width` for `layout`: the map's height follows from its width, so the panel can size itself
    /// from this view.
    public static func height(layout: KeyboardLayout, width: CGFloat) -> CGFloat {
        padding + headerHeight + spacing + mapHeight(layout: layout, width: width) + padding
    }

    private static func mapHeight(layout: KeyboardLayout, width: CGFloat) -> CGFloat {
        let bounds = EditSession.geometry(of: layout).bounds
        return ((width - 2 * padding) * bounds.height / bounds.width).rounded()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            header
            LayerMap(layout: layout, layer: layer, pressed: pressed)
                .frame(width: width - 2 * Self.padding, height: Self.mapHeight(layout: layout, width: width))
        }
        .padding(Self.padding)
        .frame(width: width)
        .modifier(HUDSurface(shape: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous), tint: tint))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var title: String { layout.layers[safe: layer]?.title ?? layer.formatted() }
    private var tint: Color? { tints ? layout.layers[safe: layer]?.color?.color : nil }

    private var header: some View {
        // On a narrow screen at Small the name keeps its width first, then the state; the hint goes before either
        // truncates.
        HStack(spacing: 10) {
            HUDIndexTile(layer: layer, color: layout.layers[safe: layer]?.color)
            Text(verbatim: title).font(.headline).lineLimit(1).layoutPriority(2)
            Text(state).font(.callout).foregroundStyle(.secondary).lineLimit(1).layoutPriority(1)
            Spacer(minLength: 12)
            LayerPips(layer: layer)
            if holder != nil, !isPreview {
                ViewThatFits(in: .horizontal) {
                    Text("release to hide").font(.caption).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                    Color.clear.frame(width: 0)
                }
            }
        }
        .frame(height: Self.headerHeight)
    }

    /// "held with ⏎", "held" for a key whose cap names the layer, "locked", or "Preview".
    private var state: String {
        if isPreview { return String(localized: "Preview") }
        guard let holder else { return String(localized: "locked") }
        guard let name = Self.keyName(layout: layout, key: holder) else { return String(localized: "held") }
        return String(localized: "held with \(name)")
    }

    /// What a key shows on the layer it went down on, as its cap draws it: "⏎". Nil for a plain layer key (MO, TT,
    /// OSL), whose cap shows the layer's name, already in the header.
    static func keyName(layout: KeyboardLayout, key: KeyRef) -> String? {
        let resolved = layout.resolvedKey(layer: key.layer, index: key.index).effective
        if resolved.customLabel == nil, resolved.tap?.isLayerAction == true { return nil }
        return Legends.legend(for: resolved, layerNames: layout.layerNames).primary.map(CapLegendView.capText) ?? "k\(key.index)"
    }

    /// "Overlay: Sym+Num layer, keys down k24, held with ⏎".
    private var accessibilityText: String {
        let map = LayerMap.accessibilityText(layout: layout, layer: layer, pressed: pressed)
        return String(localized: "Overlay: \(map), \(state)")
    }
}

/// The reminder for a locked layer (spec §8.4): "Sym+Num locked", 32 pt tall.
public struct HUDPill: View {
    var layout: KeyboardLayout
    var layer: Int
    var tints: Bool

    static let height: CGFloat = 32

    public init(layout: KeyboardLayout, layer: Int, tints: Bool = false) {
        self.layout = layout
        self.layer = layer
        self.tints = tints
    }

    public var body: some View {
        let title = layout.layers[safe: layer]?.title ?? layer.formatted()
        HStack(spacing: 8) {
            HUDIndexTile(layer: layer, color: layout.layers[safe: layer]?.color, size: 20)
            Text("\(title) locked").font(.callout.weight(.medium)).lineLimit(1)
        }
        .padding(.leading, 6)
        .padding(.trailing, 14)
        .frame(height: Self.height)
        .fixedSize()
        .modifier(HUDSurface(shape: Capsule(), tint: tints ? layout.layers[safe: layer]?.color?.color : nil))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Overlay: \(title) layer locked"))
    }
}

/// The layer's index on a tile of its color; neutral for a layer without one.
private struct HUDIndexTile: View {
    var layer: Int
    var color: HexColor?
    var size: CGFloat = 24

    var body: some View {
        let ink: Color =
            if let color { color.contrast(with: .white) >= color.contrast(with: .black) ? .white : .black } else { .primary }
        Text(verbatim: layer.formatted())
            .font(.system(size: size * 0.55, weight: .bold, design: .rounded)).monospacedDigit()
            .foregroundStyle(ink)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(color?.color ?? Tokens.neutralChip.color)
            )
            .accessibilityHidden(true)
    }
}

/// The HUD's material (spec §8.4, §10.4, §11). The panel's `NSGlassEffectView` draws the glass and its tint, so the
/// view draws nothing over it. Not ``SurfaceStyle``: where every other surface goes opaque in its own colors, the HUD
/// floats over other apps' windows and turns into an opaque dark panel, untinted, under Reduce Transparency and Increase
/// Contrast (with a stronger edge). In snapshots, where glass can't be captured, an opaque surface stands in, with the
/// tint over it.
private struct HUDSurface<S: InsettableShape>: ViewModifier {
    var shape: S
    var tint: Color?
    @Environment(\.isSnapshot) private var isSnapshot
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content
                .environment(\.colorScheme, .dark)
                .background(shape.fill(Color(white: 0.12)))
                .overlay(
                    shape.strokeBorder(.white.opacity(contrast == .increased ? 0.6 : 0.12), lineWidth: contrast == .increased ? 1 : 0.5))
        } else if isSnapshot {
            content
                .background(shape.fill(tint?.opacity(0.2) ?? .clear))
                .background(shape.fill(Tokens.surface.color))
                .overlay(shape.strokeBorder(Tokens.capEdge.color, lineWidth: 0.5))
        } else {
            content
        }
    }
}
