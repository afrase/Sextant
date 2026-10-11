import SwiftUI

/// Every app-drawn glass surface goes through here (spec §10.4, §11): Liquid Glass normally, an opaque surface
/// with a hairline and shadow under Reduce Transparency, Increase Contrast and in snapshots (glass can't be
/// captured offscreen, §13.3).
struct SurfaceStyle<S: InsettableShape>: ViewModifier {
    var shape: S
    var interactive: Bool
    @Environment(\.isSnapshot) private var isSnapshot
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if isSnapshot || reduceTransparency || contrast == .increased {
            content
                .background(shape.fill(Tokens.surface.color))
                .overlay(shape.strokeBorder(Tokens.capEdge.color, lineWidth: 0.5))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.08), radius: 3, y: 1)
        } else {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        }
    }
}

extension View {
    /// Draws this view on an app glass surface (lens-lane capsules, the legend switch, floating panels).
    func surface<S: InsettableShape>(_ shape: S, interactive: Bool = false) -> some View {
        modifier(SurfaceStyle(shape: shape, interactive: interactive))
    }
}
