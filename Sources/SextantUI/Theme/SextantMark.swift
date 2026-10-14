import SwiftUI

/// The sextant mark (spec §10.7): a 60° graduated arc with seven ticks, hung from a pivot, and an index arm.
struct SextantMark: Shape {
    func path(in rect: CGRect) -> Path {
        let pivot = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.08)
        let radius = rect.height * 0.86
        func point(_ degrees: Double, _ r: CGFloat) -> CGPoint {
            let a = Angle.degrees(degrees).radians
            return CGPoint(x: pivot.x + cos(a) * r, y: pivot.y + sin(a) * r)
        }
        var path = Path()
        path.addArc(center: pivot, radius: radius, startAngle: .degrees(60), endAngle: .degrees(120), clockwise: false)
        for degrees in [60.0, 120.0] {
            path.move(to: pivot)
            path.addLine(to: point(degrees, radius))
        }
        for tick in 0..<7 {
            let degrees = 60 + Double(tick) * 10
            path.move(to: point(degrees, radius * (tick.isMultiple(of: 3) ? 0.82 : 0.9)))
            path.addLine(to: point(degrees, radius))
        }
        path.move(to: pivot)
        path.addLine(to: point(78, radius * 0.97))
        return path
    }
}

/// The mark as one filled outline, for small sizes: the menu bar's label and the panel's header (spec §8.3). Its
/// strokes are heavier than a drawing's, so at 16 pt each stays over a point wide. While a flash writes, a band over the
/// ticks fills the arc from its left end with `progress`.
struct SextantGlyph: Shape {
    /// 0–1 while a flash writes; nil otherwise.
    var progress: Double?

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let square = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
        let pivot = CGPoint(x: square.midX, y: square.minY + side * 0.08)
        // A union, not added subpaths: outlines wound in opposite directions would cancel where they overlap.
        var glyph = SextantMark().path(in: square).strokedPath(StrokeStyle(lineWidth: side * 0.09, lineCap: .round, lineJoin: .round))
            .union(Path(ellipseIn: CGRect(x: pivot.x - side * 0.08, y: pivot.y - side * 0.07, width: side * 0.16, height: side * 0.16)))
        if let progress, progress > 0 {
            // From the limb's left end (120°) towards its right (60°), over the ticks and a third of the radius inside them:
            // a band only as deep as the ticks reads as no change at 16 pt.
            var band = Path()
            band.addArc(
                center: pivot, radius: side * 0.72, startAngle: .degrees(120), endAngle: .degrees(120 - 60 * min(progress, 1)),
                clockwise: true)
            glyph = glyph.union(band.strokedPath(StrokeStyle(lineWidth: side * 0.28, lineCap: .butt)))
        }
        return glyph
    }
}
