import SextantApplication
import SextantDomain
import SwiftUI

/// The overlay HUD (spec §8.4): a header with the layer's index tile, name, what holds it and the status lights, over
/// the layer's map with the keys held down lit. Neutral glass, optionally tinted with the layer color at 20%; an opaque
/// dark panel under Reduce Transparency.
public struct HUDView: View {
    var layout: KeyboardLayout
    var layer: Int
    /// The key holding the layer on, on the layer it went down on; nil when the layer is locked.
    var holder: KeyRef?
    var pressed: Set<Int>
    var width: CGFloat
    var tints: Bool
    /// The panel's `NSGlassEffectView` draws the glass behind this view.
    var onGlass: Bool

    public init(layout: KeyboardLayout, layer: Int, holder: KeyRef?, pressed: Set<Int>, width: CGFloat, tints: Bool = false) {
        self.init(layout: layout, layer: layer, holder: holder, pressed: pressed, width: width, tints: tints, onGlass: false)
    }

    init(layout: KeyboardLayout, layer: Int, holder: KeyRef?, pressed: Set<Int>, width: CGFloat, tints: Bool, onGlass: Bool) {
        self.layout = layout
        self.layer = layer
        self.holder = holder
        self.pressed = pressed
        self.width = width
        self.tints = tints
        self.onGlass = onGlass
    }

    static let cornerRadius: CGFloat = 24
    static let padding: CGFloat = 20

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

    public var body: some View {
        // The map's height follows from its width, so the panel can size itself from this view.
        let geometry = EditSession.geometry(of: layout).bounds
        let mapWidth = width - 2 * Self.padding
        VStack(alignment: .leading, spacing: 14) {
            header
            LayerMap(layout: layout, layer: layer, pressed: pressed)
                .frame(width: mapWidth, height: (mapWidth * geometry.height / geometry.width).rounded())
        }
        .padding(Self.padding)
        .frame(width: width)
        .modifier(
            HUDSurface(
                shape: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous), tint: tint, onGlass: onGlass)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var title: String { layout.layers[safe: layer]?.title ?? layer.formatted() }
    private var tint: Color? { tints ? layout.layers[safe: layer]?.color?.color : nil }

    private var header: some View {
        HStack(spacing: 10) {
            HUDIndexTile(layer: layer, color: layout.layers[safe: layer]?.color)
            Text(verbatim: title).font(.headline).lineLimit(1)
            Text(state).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 12)
            LayerPips(layer: layer)
            if holder != nil {
                Text("release to hide").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(height: 24)
    }

    /// "held with ⏎", or "locked".
    private var state: String {
        guard let holder else { return String(localized: "locked") }
        return String(localized: "held with \(Self.keyName(layout: layout, key: holder))")
    }

    /// What a key shows on the layer it went down on, as its cap draws it: "⏎".
    static func keyName(layout: KeyboardLayout, key: KeyRef) -> String {
        let resolved = layout.resolvedKey(layer: key.layer, index: key.index).effective
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
    var onGlass: Bool

    static let height: CGFloat = 32

    public init(layout: KeyboardLayout, layer: Int, tints: Bool = false) {
        self.init(layout: layout, layer: layer, tints: tints, onGlass: false)
    }

    init(layout: KeyboardLayout, layer: Int, tints: Bool, onGlass: Bool) {
        self.layout = layout
        self.layer = layer
        self.tints = tints
        self.onGlass = onGlass
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
        .modifier(HUDSurface(shape: Capsule(), tint: tints ? layout.layers[safe: layer]?.color?.color : nil, onGlass: onGlass))
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

/// The HUD's material (spec §10.4, §11). Glass with the optional tint, unless the panel's glass view draws it; an
/// opaque dark panel under Reduce Transparency; in snapshots, where glass can't be captured, an opaque surface with the
/// tint laid over it.
private struct HUDSurface<S: InsettableShape>: ViewModifier {
    var shape: S
    var tint: Color?
    var onGlass: Bool
    @Environment(\.isSnapshot) private var isSnapshot
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .environment(\.colorScheme, .dark)
                .background(shape.fill(Color(white: 0.12)))
                .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        } else if isSnapshot {
            content
                .background(shape.fill(tint?.opacity(0.2) ?? .clear))
                .background(shape.fill(Tokens.surface.color))
                .overlay(shape.strokeBorder(Tokens.capEdge.color, lineWidth: 0.5))
        } else if onGlass {
            content
        } else {
            content.glassEffect(tint.map { .regular.tint($0.opacity(0.2)) } ?? .regular, in: shape)
        }
    }
}
