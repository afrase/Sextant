import SwiftUI

/// Sextant's app icon (spec §10.7): a marine sextant in profile, porcelain on a graphite squircle, with a brass index arm
/// as the one accent; the mirrors and telescope are smoky graphite. Drawn on the macOS icon grid: a 1024 pt canvas,
/// transparent outside an 824 pt body at (100, 100). `scripts/icon` renders it through the `app-icon` snapshot scenes
/// into `Resources/AppIcon.icns`.
public struct AppIconArtwork: View {
    /// The pixel size being rendered. Each size has its own tier of detail (128 px and up, 64, 32, 16), with widths in
    /// whole pixels at the small ones, so render it at a scale of `pixels / 1024`.
    var pixels: CGFloat

    public init(pixels: CGFloat = 1024) { self.pixels = pixels }

    public var body: some View {
        ZStack {
            IconBody()
            Instrument(parts: IconParts(px: pixels))
        }
        .frame(width: 1024, height: 1024)
    }
}

private enum IconPalette {
    static let graphiteTop = Color(red: 0.235, green: 0.247, blue: 0.267)
    static let graphiteBottom = Color(red: 0.118, green: 0.125, blue: 0.141)
    static let ink = Color(red: 0.2, green: 0.21, blue: 0.23)
    static let porcelainHigh = Color(red: 0.96, green: 0.95, blue: 0.925)
    static let porcelainLow = Color(red: 0.84, green: 0.825, blue: 0.79)
    static let brassHigh = Color(red: 0.91, green: 0.75, blue: 0.47)
    static let brassLow = Color(red: 0.7, green: 0.53, blue: 0.29)
    static let smokeHigh = Color(red: 0.47, green: 0.49, blue: 0.53)
    static let smokeLow = Color(red: 0.22, green: 0.235, blue: 0.26)
}

// MARK: - Geometry

/// The instrument's parts in canvas coordinates (1024 pt, y down). Built in a local frame with the pivot at the origin
/// and the limb below it (90° points straight down), then tilted and centred.
private struct IconParts {
    var frame = Path()  // legs, limb, brace and pivot boss
    var ticks = Path()
    var horizonMirror = Path()
    var arm = Path()  // index arm, pivot cap and vernier pad
    var armShine = Path()  // specular line along the arm's lit edge
    var indexMirror = Path()
    var telescope = Path()
    var eyepiece = Path()  // the clamp and eyepiece bands on the telescope
    var bounds = CGRect.zero
    var bevel: CGFloat = 0  // depth of the top-lit edge in canvas pt; 0 is flat
    var lift: CGFloat = 0  // how far raised parts cast a contact shadow, in canvas pt

    // Mirrors stand across the frame, turned well off the arm's axis so neither reads as a cap on it.
    static let horizonAngle = 60.0
    static let indexAngle = 45.0

    private enum Tier { case full, mid, small, tiny }

    // swiftlint:disable:next function_body_length
    init(px: CGFloat) {  // one drawing with per-tier branches reads better than four near-copies
        let u = 1024 / px  // one output pixel in canvas pt
        let tier: Tier = px >= 128 ? .full : px >= 64 ? .mid : px >= 32 ? .small : .tiny
        let detailed = tier == .full || tier == .mid
        // Tilt puts the apex near top centre with the limb low and almost level. Half the frame angle is a true 60°
        // frame, a touch over; the limb runs `o` past each leg. At 32 and 16 px the arc opens wider and sits straighter
        // so the bottom reads as a heavy curve, not a third side.
        let tilt = Angle.degrees(tier == .tiny ? 5 : tier == .small ? 8 : 11)
        let h = detailed ? 30.5 : 33
        let o = detailed ? 3.5 : 6.0

        // Proportions per tier. Below 64 px widths are set in output pixels (u).
        let (r, limbW, legW, boss): (CGFloat, CGFloat, CGFloat, CGFloat) =
            switch tier {
            case .full: (560, 108, 56, 60)
            case .mid: (575, 120, 64, 70)
            case .small: (600, 4 * u, 2 * u, 2 * u)
            case .tiny: (620, 3 * u, 1.5 * u, 1.5 * u)
            }
        let rIn = r - limbW
        // Index arm angle. At 16 px it hangs plumb on screen, so its 1 px line sits on the pixel grid.
        let a: Double = tier == .tiny ? 90 - tilt.degrees : 104
        let armW: (CGFloat, CGFloat) =
            switch tier {
            case .full: (30, 46)
            case .mid: (40, 54)
            case .small: (2 * u, 2 * u)
            case .tiny: (u, u)
            }
        // The telescope crosses the frame at this height; its axis runs through the horizon mirror's centre.
        let ys = r * 0.5
        let legX = ys * tan(Angle.degrees(h).radians)
        let tubeH: CGFloat = tier == .full ? 50 : 56
        let mirrorAt = CGPoint(x: -legX + 6, y: ys)

        // Frame: legs from the pivot boss, the limb and a brace (from 128 px).
        var solid = Self.annulus(r0: rIn, r1: r, from: 90 - h - o, to: 90 + h + o).union(Self.circle(.zero, boss))
        for leg in [90 - h, 90 + h] {
            solid = solid.union(Self.line(.zero, Self.point(leg, rIn + 4), width: legW, cap: .round))
        }
        if tier == .full {
            let braceR = r * 0.67
            solid = solid.union(Self.annulus(r0: braceR - 15, r1: braceR + 15, from: 90 - h, to: 90 + h))
        }
        let inside = Self.sector(r: rIn + 1, from: 90 - h, to: 90 + h)
        let windows = Self.opened(inside.subtracting(solid), tier == .tiny ? 0 : tier == .small ? u : 26)
        let corner: CGFloat = tier == .full ? 18 : tier == .mid ? 22 : 0
        var plate = Self.closed(Self.opened(solid.union(inside), corner), corner).subtracting(windows)

        // Index arm: pivots at the apex, widens towards the limb and ends in a vernier pad on it.
        var armPath = Self.taper(angle: a, length: detailed ? rIn : rIn + u, w0: armW.0, w1: armW.1)
        if detailed {
            let pad: (CGFloat, CGFloat, Double) = tier == .full ? (22, 44, 6) : (26, 54, 7.5)
            armPath = armPath.union(Self.circle(.zero, 40))
                .union(Self.opened(Self.annulus(r0: rIn - pad.0, r1: rIn + pad.1, from: a - pad.2, to: a + pad.2), tier == .full ? 10 : 14))
        }

        // Telescope: a tube across the right leg, eyepiece past it. It stops short of the left leg: leg to leg it reads as an A.
        var scope = Path()
        var band = Path()
        switch tier {
        case .full:
            scope = Self.rect(x0: -22, x1: legX + 104, y: ys, height: tubeH, radius: 14)
            // Two porcelain bands: the clamp that mounts the tube on the leg, and the eyepiece.
            band = Self.rect(x0: legX - 18, x1: legX + 18, y: ys, height: tubeH + 12, radius: 6)
                .union(Self.rect(x0: legX + 64, x1: legX + 86, y: ys, height: tubeH + 12, radius: 5))
        case .mid:
            scope = Self.rect(x0: -22, x1: legX + 104, y: ys, height: tubeH, radius: tubeH / 2)
        case .small, .tiny:
            break
        }

        // Mirrors from 128 px only: at 64 px a mirror on the leg reads as a break in it.
        var horizon = Path()
        var index = Path()
        if tier == .full {
            horizon = Self.bar(center: mirrorAt, angle: Self.horizonAngle, length: 82, width: 34, radius: 8)
            index = Self.bar(center: .zero, angle: Self.indexAngle, length: 118, width: 42, radius: 9)
        }

        if tier == .mid {
            // At 64 px tone alone cannot separate tube and leg, so the tube cuts a 1.5 px dark gap round it.
            plate = plate.subtracting(scope.union(scope.strokedPath(StrokeStyle(lineWidth: 3 * u, lineCap: .round))))
        }

        var tickPath = Path()
        if detailed {
            // Graduations on the outer edge of the limb: 9 majors and 8 minors at 1024, three majors at 64 px.
            let steps: [(Double, Bool)] =
                tier == .full
                ? (0...16).map { (60 + 3.75 * Double($0), $0.isMultiple(of: 2)) }
                : [(72, true), (90, true), (108, true)]
            for (deg, major) in steps {
                let len: CGFloat = tier == .mid ? 44 : major ? 38 : 22
                tickPath = tickPath.union(
                    Self.line(Self.point(deg, r - 14 - len), Self.point(deg, r - 14), width: tier == .mid ? 20 : major ? 8 : 6, cap: .round)
                )
            }
            tickPath = tickPath.intersection(plate)
        }

        var shine = Path()
        if tier == .full {
            let n = Self.point(a + 90, 1)  // the arm's upper, lit side once tilted
            let p0 = Self.point(a, 72)
            let p1 = Self.point(a, rIn - 34)
            shine = Self.line(
                CGPoint(x: p0.x + n.x * armW.0 * 0.24, y: p0.y + n.y * armW.0 * 0.24),
                CGPoint(x: p1.x + n.x * armW.1 * 0.24, y: p1.y + n.y * armW.1 * 0.24), width: 3, cap: .round)
        }

        // Tilt, then centre the silhouette on the body (a touch high, for the shadow below).
        let rot = CGAffineTransform(rotationAngle: tilt.radians)
        let silhouette = plate.union(armPath).union(scope).union(band).union(horizon).union(index).applying(rot)
        let b = silhouette.boundingRect
        var dx = 512 - b.midX
        var dy = 506 - b.midY
        if !detailed {
            // Snap the pivot so the arm's centre line is on a pixel boundary (even width) or centre (odd).
            let odd = Int((armW.0 / u).rounded()) % 2 == 1
            dx = ((dx / u).rounded() + (odd ? 0.5 : 0)) * u
            dy = (dy / u).rounded() * u
        }
        let place = rot.concatenating(CGAffineTransform(translationX: dx, y: dy))
        horizonMirror = horizon.applying(place)
        frame = plate.applying(place)
        ticks = tickPath.applying(place)
        arm = armPath.applying(place)
        armShine = shine.applying(place)
        indexMirror = index.applying(place)
        telescope = scope.applying(place)
        eyepiece = band.applying(place)
        bounds = b.offsetBy(dx: dx, dy: dy)
        (bevel, lift) =
            switch tier {
            case .full: (5, 5)
            case .mid: (0.75 * u, 0.6 * u)
            case .small: (0.6 * u, 0.5 * u)
            case .tiny: (0, 0)
            }
    }

    static func point(_ deg: Double, _ r: CGFloat) -> CGPoint {
        let a = Angle.degrees(deg).radians
        return CGPoint(x: cos(a) * r, y: sin(a) * r)
    }

    static func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    static func line(_ p: CGPoint, _ q: CGPoint, width: CGFloat, cap: CGLineCap) -> Path {
        Path {
            $0.move(to: p)
            $0.addLine(to: q)
        }
        .strokedPath(StrokeStyle(lineWidth: width, lineCap: cap))
    }

    static func rect(x0: CGFloat, x1: CGFloat, y: CGFloat, height: CGFloat, radius: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: x0, y: y - height / 2, width: x1 - x0, height: height), cornerRadius: radius, style: .continuous)
    }

    /// A rounded rectangle centred on `center` with its long side along `angle`.
    static func bar(center: CGPoint, angle: Double, length: CGFloat, width: CGFloat, radius: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: -length / 2, y: -width / 2, width: length, height: width), cornerRadius: radius, style: .continuous)
            .applying(
                CGAffineTransform(rotationAngle: Angle.degrees(angle).radians).concatenating(
                    CGAffineTransform(translationX: center.x, y: center.y)))
    }

    /// A bar from the origin along `angle`, `w0` wide at the origin and `w1` at the far end.
    static func taper(angle: Double, length: CGFloat, w0: CGFloat, w1: CGFloat) -> Path {
        let e = point(angle, length)
        let n = point(angle + 90, 1)
        return Path { p in
            p.addLines([
                CGPoint(x: n.x * w0 / 2, y: n.y * w0 / 2),
                CGPoint(x: e.x + n.x * w1 / 2, y: e.y + n.y * w1 / 2),
                CGPoint(x: e.x - n.x * w1 / 2, y: e.y - n.y * w1 / 2),
                CGPoint(x: -n.x * w0 / 2, y: -n.y * w0 / 2),
            ])
            p.closeSubpath()
        }
    }

    static func sector(r: CGFloat, from a0: Double, to a1: Double) -> Path {
        Path { p in
            p.move(to: .zero)
            p.addArc(center: .zero, radius: r, startAngle: .degrees(a0), endAngle: .degrees(a1), clockwise: false)
            p.closeSubpath()
        }
    }

    static func annulus(r0: CGFloat, r1: CGFloat, from a0: Double, to a1: Double) -> Path {
        Path { p in
            p.addArc(center: .zero, radius: r1, startAngle: .degrees(a0), endAngle: .degrees(a1), clockwise: false)
            p.addArc(center: .zero, radius: r0, startAngle: .degrees(a1), endAngle: .degrees(a0), clockwise: true)
            p.closeSubpath()
        }
    }

    /// Rounds convex corners by `c` (erode, then dilate).
    static func opened(_ p: Path, _ c: CGFloat) -> Path {
        guard c > 0 else { return p }
        let ring = StrokeStyle(lineWidth: c * 2, lineCap: .round, lineJoin: .round)
        let core = p.subtracting(p.strokedPath(ring))
        return core.union(core.strokedPath(ring))
    }

    /// Fills concave corners with a radius `c` fillet (dilate, then erode).
    static func closed(_ p: Path, _ c: CGFloat) -> Path {
        guard c > 0 else { return p }
        let ring = StrokeStyle(lineWidth: c * 2, lineCap: .round, lineJoin: .round)
        let grown = p.union(p.strokedPath(ring))
        return grown.subtracting(grown.strokedPath(ring))
    }
}

// MARK: - Layers

private struct IconBody: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 185.4, style: .continuous)
        shape
            .fill(LinearGradient(colors: [IconPalette.graphiteTop, IconPalette.graphiteBottom], startPoint: .top, endPoint: .bottom))
            .overlay(
                shape.fill(
                    RadialGradient(colors: [.white.opacity(0.07), .clear], center: UnitPoint(x: 0.5, y: 0), startRadius: 0, endRadius: 560))
            )
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.22), .white.opacity(0.03), .white.opacity(0.07)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 3)
            )  // a glint along the top edge, faint down the sides
            .frame(width: 824, height: 824)
            .shadow(color: .black.opacity(0.3), radius: 14, y: 10)
            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
            .position(x: 512, y: 512)
    }
}

private struct Instrument: View {
    var parts: IconParts

    /// A top-to-bottom gradient spanning `rect` (canvas pt).
    func gradient(_ high: Color, _ low: Color, over rect: CGRect) -> LinearGradient {
        LinearGradient(
            colors: [high, low], startPoint: UnitPoint(x: 0.5, y: rect.minY / 1024), endPoint: UnitPoint(x: 0.5, y: rect.maxY / 1024))
    }

    func smoke(_ shape: Path) -> LinearGradient { gradient(IconPalette.smokeHigh, IconPalette.smokeLow, over: shape.boundingRect) }

    var body: some View {
        let porcelain = gradient(IconPalette.porcelainHigh, IconPalette.porcelainLow, over: parts.bounds)
        let d = parts.bevel
        let s = parts.lift
        ZStack {
            Bevelled(shape: parts.frame, fill: porcelain, depth: d)
            parts.ticks.fill(IconPalette.ink.opacity(0.45))
            Bevelled(shape: parts.horizonMirror, fill: smoke(parts.horizonMirror), depth: d * 0.7, rim: d > 0)
                .shadow(color: .black.opacity(0.3), radius: s * 0.6, y: s * 0.5)
            Bevelled(
                shape: parts.arm, fill: gradient(IconPalette.brassHigh, IconPalette.brassLow, over: parts.arm.boundingRect), depth: d * 0.8
            )
            // Contact shadow where the arm lies on the frame, then a softer drop.
            .shadow(color: .black.opacity(0.4), radius: s * 0.5, y: s * 0.6)
            .shadow(color: .black.opacity(0.18), radius: s * 1.6, y: s * 1.4)
            parts.armShine.fill(.white.opacity(0.6)).blur(radius: 0.6)
            Bevelled(shape: parts.indexMirror, fill: smoke(parts.indexMirror), depth: d * 0.7, rim: true)
                .shadow(color: .black.opacity(0.35), radius: s * 0.6, y: s * 0.6)
            Bevelled(shape: parts.telescope, fill: smoke(parts.telescope), depth: d * 0.8, rim: d > 0)
                .shadow(color: .black.opacity(0.4), radius: s * 0.8, y: s * 0.8)
            Bevelled(shape: parts.eyepiece, fill: porcelain, depth: d * 0.6)
        }
        .frame(width: 1024, height: 1024)
        .compositingGroup()
        // Contact shadow close under the porcelain, plus a soft drop onto the plate.
        .shadow(color: .black.opacity(0.4), radius: 3, y: 3)
        .shadow(color: .black.opacity(0.35), radius: 20, y: 16)
    }
}

/// A raised part lit from above: a bright lip along every upward-facing edge (outer tops and the lower rims of holes), a
/// darker shade along the downward-facing ones, and optionally a faint rim so dark parts keep their edge on graphite.
private struct Bevelled<Fill: ShapeStyle>: View {
    var shape: Path
    var fill: Fill
    var depth: CGFloat
    var rim = false

    var body: some View {
        shape.fill(fill)
            .overlay {
                if depth > 0 {
                    shape.subtracting(shape.offsetBy(dx: 0, dy: depth)).fill(.white.opacity(0.95)).blur(radius: depth * 0.25)
                    shape.subtracting(shape.offsetBy(dx: 0, dy: -depth * 1.4)).fill(.black.opacity(0.2)).blur(radius: depth * 0.35)
                }
                if rim { shape.stroke(.white.opacity(0.28), lineWidth: 3) }
            }
            .clipShape(shape)
    }
}
