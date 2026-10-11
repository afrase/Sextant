import SwiftUI

/// The content surface behind the canvas: base colour with a soft radial lift (spec §4.10). Never glass.
struct Bench: View {
    var body: some View {
        ZStack {
            Tokens.benchBase.color
            RadialGradient(
                colors: [Tokens.benchLift.color, Tokens.benchBase.color], center: .init(x: 0.5, y: 0.46), startRadius: 0, endRadius: 700)
        }
    }
}

/// What the board area draws on the bench behind the keys: the precision grid on the key pitch and the layer
/// atmosphere (spec §4.5, §4.10). Both are off under Increase Contrast.
struct BenchBackdrop: View {
    /// The board's frame in the board area.
    var boardRect: CGRect
    var pitch: CGFloat
    /// A point where grid lines cross, so the grid lines up with the keys.
    var gridAnchor: CGPoint
    /// The shown layer's tones; nil on the base layer and on layers without a colour.
    var wash: LayerTones?
    var layer: Int
    var showsGrid: Bool
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if contrast != .increased {
                if showsGrid { BenchGridLines(boardRect: boardRect, pitch: pitch, gridAnchor: gridAnchor) }
                ZStack {
                    if let wash {
                        Rectangle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        wash.display.color.opacity(colorScheme == .dark ? 0.07 : 0.05), wash.display.color.opacity(0),
                                    ],
                                    center: .center, startRadius: 0, endRadius: 0.6 * boardRect.width)
                            )
                            .frame(width: 1.2 * boardRect.width, height: 1.2 * boardRect.width)
                            .position(x: boardRect.midX, y: boardRect.midY)
                            .id(layer)
                            .transition(.opacity)
                    }
                }
                .animation(SextantMotion.atmosphere, value: layer)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Hairlines on the key pitch, at full strength up to 1.5 pitch beyond the board and gone 1.5 pitch later. A view of
/// its own, so a layer change (which changes the atmosphere) doesn't redraw it.
private struct BenchGridLines: View {
    var boardRect: CGRect
    var pitch: CGFloat
    /// A point where grid lines cross, so the grid lines up with the keys.
    var gridAnchor: CGPoint
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let hairline = 1 / displayScale
        return Canvas { ctx, _ in
            let p = pitch
            guard p > 0 else { return }
            let region = boardRect.insetBy(dx: -3 * p, dy: -3 * p)
            let color = Tokens.benchGrid.color
            func strength(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> Double {
                let d = v < lo ? lo - v : v > hi ? v - hi : 0
                return max(0, min(1, 2 - d / (1.5 * p)))
            }
            // Each line fades along its length with a gradient, and across the lines by its own distance.
            func line(from a: CGPoint, to b: CGPoint, alpha: Double, fadeStart: CGFloat, fadeEnd: CGFloat) {
                guard alpha > 0 else { return }
                let stops: [Gradient.Stop] = [
                    .init(color: color.opacity(0), location: 0), .init(color: color.opacity(alpha), location: fadeStart),
                    .init(color: color.opacity(alpha), location: fadeEnd), .init(color: color.opacity(0), location: 1),
                ]
                var path = Path()
                path.move(to: a)
                path.addLine(to: b)
                ctx.stroke(path, with: .linearGradient(Gradient(stops: stops), startPoint: a, endPoint: b), lineWidth: hairline)
            }
            let inset = 1.5 * p / region.height, insetX = 1.5 * p / region.width
            var x = gridAnchor.x + ((region.minX - gridAnchor.x) / p).rounded(.up) * p
            while x <= region.maxX {
                line(
                    from: CGPoint(x: x, y: region.minY), to: CGPoint(x: x, y: region.maxY),
                    alpha: strength(x, boardRect.minX, boardRect.maxX), fadeStart: inset, fadeEnd: 1 - inset)
                x += p
            }
            var y = gridAnchor.y + ((region.minY - gridAnchor.y) / p).rounded(.up) * p
            while y <= region.maxY {
                line(
                    from: CGPoint(x: region.minX, y: y), to: CGPoint(x: region.maxX, y: y),
                    alpha: strength(y, boardRect.minY, boardRect.maxY), fadeStart: insetX, fadeEnd: 1 - insetX)
                y += p
            }
        }
    }
}
