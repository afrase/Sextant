import AppKit
import SextantApplication
import SextantDomain
import SwiftUI

/// The Combos board's drawing over the caps (spec §6.4): a 2 pt trace joining each combo's keys, shown only in the gaps
/// between caps, and an output pill in the combo's colour, placed where it covers no legend and no number. The caps'
/// rings, numbers and dimming come from the cap decoration (``LayoutWindowModel/comboDecoration(index:)``).
/// Drawn in the board area's space, so a pill can sit beside the board when there is no room between the keys.
struct ComboOverlay: View {
    var board: BoardLayout
    /// The board's top-left corner in the board area.
    var origin: CGPoint
    /// The board area.
    var size: CGSize
    @Environment(\.layoutWindow) private var window
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let window, window.page == .combos, let session = window.session {
            let drawn = window.draftCombo.map { [$0] } ?? window.focusedCombos
            let area = CGRect(origin: CGPoint(x: -origin.x, y: -origin.y), size: size).insetBy(dx: 4, dy: 4)
            let legends = ComboPills.legendRects(
                layout: session.layout, layer: session.selection.layer, mode: window.legendMode, board: board)
            let pills = ComboPills.place(drawn, layout: session.layout, legends: legends, board: board, area: area)
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in traces(drawn, in: &context) }
                ForEach(pills, id: \.item.id) { pill($0) }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .allowsHitTesting(false)
            // The caps' VoiceOver values name each combo they are in.
            .accessibilityHidden(true)
        }
    }

    /// Each combo's keys joined by the shortest tree of lines between their centres, with every cap cut out of it.
    private func traces(_ drawn: [NumberedCombo], in context: inout GraphicsContext) {
        context.translateBy(x: origin.x, y: origin.y)
        context.drawLayer { layer in
            for item in drawn {
                var path = Path()
                for (a, b) in ComboPills.tree(item.combo.keyIndices.compactMap { board.frames[safe: $0]?.center }) {
                    path.move(to: a)
                    path.addLine(to: b)
                }
                layer.stroke(path, with: .color(item.color.color), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            layer.blendMode = .destinationOut
            for var frame in board.frames {
                frame.size = CGSize(width: frame.size.width + 1, height: frame.size.height + 1)
                layer.fill(Path { $0.addLines(frame.corners) }, with: .color(.black))
            }
        }
    }

    private func pill(_ pill: ComboPills.Pill) -> some View {
        let token = pill.item.color
        // Black or white by the fill's luminance: at least 4.5:1 on every palette colour (TokenContrastTests).
        let fill = colorScheme == .dark ? token.dark : token.light
        let ink: Color = fill.luminance > 0.179 ? .black : .white
        return HStack(spacing: ComboPills.spacing) {
            Text(verbatim: "\(pill.item.number)").opacity(0.7)
            Text(verbatim: pill.text)
        }
        .font(.system(size: pill.fontSize, weight: .semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .foregroundStyle(ink)
        .frame(width: pill.rect.width, height: pill.rect.height)
        .background(Capsule().fill(token.color))
        .position(x: pill.rect.midX + origin.x, y: pill.rect.midY + origin.y)
    }
}

/// Where the output pills go (spec §6.4), from the key frames alone, so a test can check that none covers a legend.
enum ComboPills {
    struct Pill {
        var item: NumberedCombo
        var text: String
        var fontSize: CGFloat
        /// In board points.
        var rect: CGRect
    }

    /// Between the number and the output.
    static let spacing: CGFloat = 3

    /// Places a pill per combo that sends something, in order, each as near as it fits to the middle of the gap above its
    /// keys, else further out, beside or above the board within `area` (board points). Never over a legend
    /// (``legendRects(layout:layer:mode:board:)``), a number badge, the Navigator or another pill; a pill with no room
    /// left is left out.
    static func place(_ combos: [NumberedCombo], layout: KeyboardLayout, legends: [CGRect], board: BoardLayout, area: CGRect) -> [Pill] {
        let cap = board.keySize
        let fontSize = max(9, (0.16 * cap).rounded())
        let height = max(14, (fontSize * 1.6).rounded())
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        func width(_ text: String) -> CGFloat { ceil(NSAttributedString(string: text, attributes: [.font: font]).size().width) }
        var obstacles = legends
        // The number badges on the drawn combos' keys.
        let numbered = Set(combos.flatMap(\.combo.keyIndices))
        obstacles += board.frames.filter { numbered.contains($0.index) }.map(numberRect)
        if let nav = board.navigator {
            obstacles.append(
                CGRect(x: nav.center.x - nav.diameter / 2, y: nav.center.y - nav.diameter / 2, width: nav.diameter, height: nav.diameter))
        }
        var pills: [Pill] = []
        for item in combos where !item.combo.output.isNone && !item.combo.output.isTransparent {
            let members = item.combo.keyIndices.compactMap { board.frames[safe: $0]?.boundingBox }
            guard let box = members.first.map({ members.reduce($0) { $0.union($1) } }) else { continue }
            let text = ComboText.output(item.combo.output, in: layout)
            let size = CGSize(width: width("\(item.number)") + spacing + width(text) + height * 0.8, height: height)
            let preferred = CGPoint(x: box.midX, y: box.minY - size.height / 2)
            guard let rect = spot(for: size, near: preferred, step: max(2, cap / 8), area: area, avoiding: obstacles) else { continue }
            pills.append(Pill(item: item, text: text, fontSize: fontSize, rect: rect))
            obstacles.append(rect.insetBy(dx: -2, dy: -2))
        }
        return pills
    }

    /// The nearest free spot to `preferred`, searching outward ring by ring on a `step` grid. Spots below the preferred
    /// point count as further away, so a pill goes above its keys when it can.
    static func spot(for size: CGSize, near preferred: CGPoint, step: CGFloat, area: CGRect, avoiding obstacles: [CGRect]) -> CGRect? {
        // Six keys out at most: further off, a pill no longer reads as its combo's.
        let reach = min(Int((max(area.width, area.height) / step).rounded(.up)), 48)
        func score(_ i: Int, _ j: Int) -> Double { Double(i * i) + Double(j * j) * (j > 0 ? 2.5 : 1) }
        for ring in 0...reach {
            var ringPoints: [(Int, Int)] = []
            for i in -ring...ring {
                for j in -ring...ring where max(abs(i), abs(j)) == ring { ringPoints.append((i, j)) }
            }
            for (i, j) in ringPoints.sorted(by: { score($0.0, $0.1) < score($1.0, $1.1) }) {
                let center = CGPoint(x: preferred.x + CGFloat(i) * step, y: preferred.y + CGFloat(j) * step)
                let rect = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
                if area.contains(rect), !obstacles.contains(where: { $0.intersects(rect) }) { return rect }
            }
        }
        return nil
    }

    /// Every cap's legend zone, as a box around the rotated cap's zone (spec §4.2): the band and the 70% above it on a
    /// key with a hold band, the middle 60% otherwise, between the cap's side paddings.
    static func legendRects(layout: KeyboardLayout, layer: Int, mode: LegendMode, board: BoardLayout) -> [CGRect] {
        board.frames.map { frame in
            let model = KeyCapModel(layout: layout, layer: layer, index: frame.index, mode: mode)
            let banded = model.band != nil || model.isHoldOnly
            let (w, h) = (frame.size.width, frame.size.height)
            let (top, bottom) = banded ? (0.12, 1.0) : (0.2, 0.8)
            let local = [
                CGPoint(x: -0.44 * w, y: (top - 0.5) * h), CGPoint(x: 0.44 * w, y: (top - 0.5) * h),
                CGPoint(x: 0.44 * w, y: (bottom - 0.5) * h), CGPoint(x: -0.44 * w, y: (bottom - 0.5) * h),
            ]
            return box(local.map { rotate($0, frame) })
        }
    }

    /// The top-left number badge: 14 pt, 4 pt outside the corner (KeyCap), with a point to spare.
    static func numberRect(_ frame: BoardLayout.KeyFrame) -> CGRect {
        let center = rotate(CGPoint(x: -frame.size.width / 2 + 3, y: -frame.size.height / 2 + 3), frame)
        return CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16)
    }

    /// The shortest tree joining the points (Prim's), as line segments.
    static func tree(_ points: [CGPoint]) -> [(CGPoint, CGPoint)] {
        guard let first = points.first else { return [] }
        var joined = [first], rest = Array(points.dropFirst()), edges: [(CGPoint, CGPoint)] = []
        func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
        while !rest.isEmpty {
            var best: (from: CGPoint, to: Int, d: CGFloat)?
            for a in joined {
                for (i, b) in rest.enumerated() where best.map({ distance(a, b) < $0.d }) ?? true { best = (a, i, distance(a, b)) }
            }
            guard let best else { break }
            let next = rest.remove(at: best.to)
            edges.append((best.from, next))
            joined.append(next)
        }
        return edges
    }

    /// A point given relative to the cap's centre, upright, turned with the cap onto the board.
    private static func rotate(_ p: CGPoint, _ frame: BoardLayout.KeyFrame) -> CGPoint {
        let r = frame.rotation * .pi / 180
        return CGPoint(x: frame.center.x + p.x * cos(r) - p.y * sin(r), y: frame.center.y + p.x * sin(r) + p.y * cos(r))
    }

    private static func box(_ points: [CGPoint]) -> CGRect {
        let xs = points.map(\.x), ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return .null }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
