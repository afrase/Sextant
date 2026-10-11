import SwiftUI

/// Sextant's app icon (spec §10.7): a graphite squircle with the porcelain sextant mark resting on two tilted generic
/// keycaps (no Voyager outline). Drawn on the macOS icon grid: a 1024 pt canvas, transparent outside an 824 pt body at
/// (100, 100). Three clear values (graphite, slate keys, porcelain mark) keep the arc and both keys legible at 16 px.
/// `scripts/icon` renders it through the `app-icon` snapshot scenes into `Resources/AppIcon.icns`.
///
/// The mark is SextantMark's geometry (pivot on top, a 60° sector, the index arm at 78°) built from filled shapes,
/// because an icon needs heavy bands and cut-in ticks rather than a hairline stroke.
public struct AppIconArtwork: View {
    /// The 16 and 32 px artwork: no ticks or hub hole, and a heavier index arm.
    var small: Bool

    public init(small: Bool = false) { self.small = small }

    public var body: some View {
        ZStack {
            IconBody()
            IconKeys()  // with a graphite gap cut where the arc lies over them
                .overlay { MarkSilhouette(part: .all, grow: IconGeo.halo * 2, small: small).blendMode(.destinationOut) }
                .compositingGroup()
                .shadow(color: .black.opacity(0.25), radius: 8, y: 6)
            // Stacked like the instrument: frame and scale, then the index arm, then the pivot.
            ZStack {
                porcelain(.frame)
                porcelain(.arm).shadow(color: .black.opacity(0.24), radius: 5, y: 3)
                porcelain(.hub).shadow(color: .black.opacity(0.2), radius: 3, y: 2)
            }
            .overlay {
                if !small {  // the pivot hole, through every layer
                    Circle().fill(.black).frame(width: 40, height: 40).position(IconGeo.pivot).blendMode(.destinationOut)
                }
            }
            .compositingGroup()
            .shadow(color: .black.opacity(0.35), radius: 12, y: 8)
        }
        .frame(width: 1024, height: 1024)
    }

    /// Enamel: a top-to-bottom porcelain face with a bright top edge and a shaded bottom edge.
    private func porcelain(_ part: MarkSilhouette.Part) -> some View {
        let shape = MarkSilhouette(part: part, grow: 0, small: small)
        return ZStack {
            IconPalette.porcelainShade
            Color.white.mask { shape.offset(y: -2) }
            LinearGradient(colors: [IconPalette.porcelainTop, IconPalette.porcelainBottom], startPoint: .top, endPoint: .bottom)
                .mask { shape.offset(y: -2) }
                .mask { shape.offset(y: 2) }
        }
        .mask { shape }
    }
}

// MARK: - Geometry (1024 pt canvas, y down; angles clockwise from +x, as in SextantMark)

private enum IconGeo {
    static let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    static let cornerRadius: CGFloat = 185.4
    static let pivot = CGPoint(x: 512, y: 226)
    static let radius: CGFloat = 388  // centreline of the sector outline
    static let frameWidth: CGFloat = 40  // the two radial arms
    static let bandWidth: CGFloat = 96  // the graduated arc
    static let indexAngle = 78.0  // where SextantMark's index arm points
    static let hubR: CGFloat = 58
    static let halo: CGFloat = 28
    // Key centres, mirrored about x = 512: the narrowest gap between them is about 140 pt, 2 px at 16 px.
    static let keyDX: CGFloat = 188
    static let keyY: CGFloat = 704
    static let keyTilt = 10.0  // tops turned in towards the pivot
    static let keySize: CGFloat = 214

    static var outer: CGFloat { radius + frameWidth / 2 }

    static func point(_ degrees: Double, _ r: CGFloat) -> CGPoint {
        let a = Angle.degrees(degrees).radians
        return CGPoint(x: pivot.x + cos(a) * r, y: pivot.y + sin(a) * r)
    }
}

private enum IconPalette {
    static let graphiteTop = Color(red: 0.235, green: 0.247, blue: 0.267)
    static let graphiteBottom = Color(red: 0.125, green: 0.133, blue: 0.149)
    static let porcelainTop = Color(red: 0.98, green: 0.973, blue: 0.953)
    static let porcelainBottom = Color(red: 0.9, green: 0.884, blue: 0.853)
    static let porcelainShade = Color(red: 0.74, green: 0.725, blue: 0.7)
    static let keyBase = Color(red: 0.38, green: 0.4, blue: 0.44)
    static let keyTopLight = Color(red: 0.54, green: 0.57, blue: 0.62)
    static let keyTopDark = Color(red: 0.49, green: 0.515, blue: 0.565)
}

// MARK: - Layers

private struct IconBody: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: IconGeo.cornerRadius, style: .continuous)
        shape
            .fill(LinearGradient(colors: [IconPalette.graphiteTop, IconPalette.graphiteBottom], startPoint: .top, endPoint: .bottom))
            .overlay(shape.fill(RadialGradient(colors: [.white.opacity(0.1), .clear], center: .top, startRadius: 0, endRadius: 560)))
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.3), .clear], startPoint: .top, endPoint: .center), lineWidth: 2.5)
            )  // a glint along the top edge that fades down the sides
            .frame(width: IconGeo.body.width, height: IconGeo.body.height)
            .shadow(color: .black.opacity(0.32), radius: 14, y: 10)
            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
            .position(x: IconGeo.body.midX, y: IconGeo.body.midY)
    }
}

/// The sextant mark (SextantMark's geometry, thickened) as an alpha silhouette, one part at a time.
/// `grow` widens every shape and drops the details, which is how the halo is cut.
private struct MarkSilhouette: View {
    enum Part { case frame, arm, hub, all }
    var part: Part
    var grow: CGFloat
    var small: Bool

    var body: some View {
        ZStack {
            if part == .frame || part == .all {
                if grow == 0 { sector.fill(.white.opacity(0.13)) }  // a faint plate inside the frame
                sector.stroke(style: StrokeStyle(lineWidth: IconGeo.frameWidth + grow, lineJoin: .round))
                band.stroke(style: StrokeStyle(lineWidth: IconGeo.bandWidth + grow, lineCap: .butt))
                if grow == 0 && !small {
                    Group {
                        ticks(major: false).stroke(style: StrokeStyle(lineWidth: 11, lineCap: .round))
                        ticks(major: true).stroke(style: StrokeStyle(lineWidth: 20, lineCap: .round))
                    }
                    .blendMode(.destinationOut)
                }
            }
            if part == .arm || part == .all { index(grow: grow) }
            if part == .hub || part == .all {
                Circle().frame(width: IconGeo.hubR * 2 + grow, height: IconGeo.hubR * 2 + grow).position(IconGeo.pivot)
            }
        }
        .foregroundStyle(.black)  // an opaque alpha source: the default label colour is not fully opaque
        .compositingGroup()
    }

    /// Pivot, both radial arms and the arc: a closed 60° sector.
    private var sector: Path {
        var p = Path()
        p.move(to: IconGeo.pivot)
        p.addLine(to: IconGeo.point(120, IconGeo.radius))
        p.addArc(center: IconGeo.pivot, radius: IconGeo.radius, startAngle: .degrees(120), endAngle: .degrees(60), clockwise: true)
        p.closeSubpath()
        return p
    }

    /// The thick graduated band; its outer edge matches the frame's, its ends hide inside the arms.
    private var band: Path {
        Path { p in
            p.addArc(
                center: IconGeo.pivot, radius: IconGeo.outer - IconGeo.bandWidth / 2, startAngle: .degrees(60), endAngle: .degrees(120),
                clockwise: false)
        }
    }

    /// Graduations cut into the band from its outer edge: 10° apart, the middle one long and wide enough to show at 64 px.
    private func ticks(major: Bool) -> Path {
        Path { p in
            for tick in 1..<6 where tick.isMultiple(of: 3) == major {
                let degrees = 60 + Double(tick) * 10
                p.move(to: IconGeo.point(degrees, IconGeo.outer - 18))
                p.addLine(to: IconGeo.point(degrees, IconGeo.outer - (major ? 72 : 46)))
            }
        }
    }

    /// The index arm: tapers from the hub to a rounded tip that rests on the band's outer edge.
    private func index(grow: CGFloat) -> Path {
        let w0 = (small ? 100 : 76) + grow
        let w1 = (small ? 70 : 46) + grow
        let a = Angle.degrees(IconGeo.indexAngle).radians
        let normal = CGVector(dx: -sin(a), dy: cos(a))
        let tip = IconGeo.point(IconGeo.indexAngle, IconGeo.outer - w1 / 2 + grow / 2)
        func offset(_ p: CGPoint, _ d: CGFloat) -> CGPoint { CGPoint(x: p.x + normal.dx * d, y: p.y + normal.dy * d) }
        var p = Path()
        p.move(to: offset(IconGeo.pivot, w0 / 2))
        p.addLine(to: offset(tip, w1 / 2))
        p.addArc(center: tip, radius: w1 / 2, startAngle: .radians(a + .pi / 2), endAngle: .radians(a - .pi / 2), clockwise: true)
        p.addLine(to: offset(IconGeo.pivot, -w0 / 2))
        p.closeSubpath()
        return p
    }
}

/// Two generic keycaps, mirrored about the centre line, their tops leaning in.
private struct IconKeys: View {
    var body: some View {
        ZStack {
            ForEach([-1.0, 1.0], id: \.self) { side in
                IconKeycap()
                    .rotationEffect(.degrees(-side * IconGeo.keyTilt))
                    .position(x: 512 + side * IconGeo.keyDX, y: IconGeo.keyY)
            }
        }
    }
}

/// A keycap seen from slightly in front: a skirt with a cooler, lit top face set back towards the top.
private struct IconKeycap: View {
    var body: some View {
        let s = IconGeo.keySize
        let face = RoundedRectangle(cornerRadius: s * 0.17, style: .continuous)
        ZStack {
            RoundedRectangle(cornerRadius: s * 0.22, style: .continuous).fill(IconPalette.keyBase)
            face.fill(LinearGradient(colors: [IconPalette.keyTopLight, IconPalette.keyTopDark], startPoint: .top, endPoint: .bottom))
                .overlay(
                    face.strokeBorder(
                        LinearGradient(colors: [IconPalette.porcelainTop.opacity(0.55), .clear], startPoint: .top, endPoint: .center),
                        lineWidth: 3)
                )
                .frame(width: s * 0.78, height: s * 0.7)
                .offset(y: -s * 0.08)
        }
        .frame(width: s, height: s)
        .shadow(color: .black.opacity(0.35), radius: 3, y: 4)  // contact shadow
    }
}
