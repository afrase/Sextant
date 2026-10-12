import CoreGraphics  // value types only (CGPoint, CGSize, CGRect); ADR 0008
import Foundation

/// Physical key positions for a board, in **key units** (1u = key pitch: key plus gap), y growing downward.
///
/// `BoardGeometry.voyager` is built from ``BoardDefinition/voyager`` (column stagger, home row, matrix,
/// QMK and LED coordinates) and calibrated against Oryx's own render
/// (`docs/oryx-ui/01-layout-readonly-main.jpg`, kept outside the repo in the reference folder):
/// - Column stagger: columns 2 and 4 of each half are raised 0.15u and the middle-finger column 0.30u
///   (Oryx's `translateY(-15% / -30%)`); `.qmk` uses QMK `keyboard.json`'s 0.25u / 0.5u instead.
/// - Thumbs: per half, a 1u key (24 / 51) and a taller 1u × 1.35u key (25 / 50) sharing a top edge,
///   rotated +30° (left) / −30° (right) about the cluster centre. The research JSON lists both thumbs
///   square; Oryx actually draws the inner one taller, which this geometry follows.
/// - Halves: 3.0u apart by default (spec §4.1; Oryx draws 4.9u), adjustable with `halfGap`.
///
/// Use ``layout(keySize:spacing:padding:)`` to get point frames.
public struct BoardGeometry: Hashable, Sendable {
    public enum Hand: String, Hashable, Sendable, CaseIterable { case left, right }
    public enum Cluster: String, Hashable, Sendable { case main, thumb }
    /// Column-stagger profile.
    public enum Stagger: String, Hashable, Sendable {
        /// 0.15u / 0.30u, as Oryx draws it (default).
        case oryx
        /// 0.25u / 0.5u, from QMK `keyboard.json`.
        case qmk
    }
    /// Arrow-key directions for ``neighbor(of:toward:)``.
    public enum Direction: Hashable, Sendable { case left, right, up, down }

    /// Firmware matrix position (row 0-11, column 0-6) as used by live key events.
    public struct MatrixPosition: Hashable, Sendable {
        public var row: Int
        public var column: Int
    }

    /// One key's shape.
    public struct KeyShape: Identifiable, Hashable, Sendable {
        /// Oryx key index (= QMK `kNN` = RGB LED index).
        public var index: Int
        public var id: Int { index }
        public var hand: Hand
        public var cluster: Cluster
        /// Row 0-3 for main keys, 4 for thumbs.
        public var row: Int
        /// Column 0-5; on the left half 0 is the outer (pinky) column, on the right half 0 is the inner (index) column.
        public var column: Int
        /// Centre in key units.
        public var center: CGPoint
        /// Size in key units (before any spacing is removed).
        public var size: CGSize
        /// Rotation in degrees, clockwise positive (SwiftUI `.rotationEffect(.degrees(rotation))`).
        public var rotation: Double
        public var isHomeRow: Bool
        public var matrix: MatrixPosition?
        /// QMK `keyboard.json` top-left position in units (reference only).
        public var qmkPosition: CGPoint?
        /// LED coordinate in QMK's 224×64 rgb_matrix space (reference only).
        public var ledPosition: CGPoint?

        /// Corners in key units (clockwise from top-left before rotation).
        public var corners: [CGPoint] { BoardGeometry.corners(center: center, size: size, rotation: rotation) }
        /// Axis-aligned bounds of the rotated key, in key units.
        public var boundingBox: CGRect { BoardGeometry.box(corners) }
    }

    /// Where a Navigator (trackpad/trackball) sits, as Oryx places it: by the inner edge of a half.
    public struct NavigatorAnchor: Hashable, Sendable {
        public var hand: Hand
        public var center: CGPoint
        /// Diameter in key units.
        public var diameter: Double
    }

    public var name: String
    /// All keys, ordered by index.
    public var keys: [KeyShape]
    public var navigator: NavigatorAnchor?
    /// Distance between the halves' inner edges, in key units.
    public var halfGap: Double
    public var stagger: Stagger

    /// The default Voyager geometry (Oryx stagger, 3.0u half gap, Navigator anchor on the right).
    public static let voyager: BoardGeometry = .voyager()

    /// Builds Voyager geometry.
    /// - Parameters:
    ///   - stagger: column-stagger profile.
    ///   - halfGap: space between the halves' inner edges in key units. Values below 2.4 are clamped so the thumb clusters can't overlap.
    ///   - navigator: side carrying a Navigator anchor, or nil.
    public static func voyager(stagger: Stagger = .oryx, halfGap: Double = 3.0, navigator: Hand? = .right) -> Self {
        let gap = max(2.4, halfGap)
        let width = 12 + gap
        let board = BoardDefinition.voyager
        var keys: [KeyShape] = []
        // Thumb cluster (left half; the right half mirrors it). Calibrated to Oryx's render.
        let pivot = CGPoint(x: 6.04, y: 5.18)
        let thumbAngle = 30.0
        let outerLocal = CGPoint(x: -0.5, y: 0)  // key 24: 1u × 1u
        let innerLocal = CGPoint(x: 0.5, y: 0.175)  // key 25: 1u × 1.35u, tops aligned
        func rotate(_ p: CGPoint, _ deg: Double) -> CGPoint {
            let r = deg * .pi / 180
            return CGPoint(x: p.x * cos(r) - p.y * sin(r), y: p.x * sin(r) + p.y * cos(r))
        }
        for m in board.keys {
            let index = m.index
            let matrix = MatrixPosition(row: m.matrixRow, column: m.matrixColumn)
            let hand: Hand = index <= 25 ? .left : .right
            var shape: KeyShape
            if (0...23).contains(index) || (26...49).contains(index) {
                let local = hand == .left ? index : index - 26
                let row = local / 6, col = local % 6
                // Left column c and right column (5 - c) mirror each other.
                let mirrorCol = hand == .left ? col : 5 - col
                // Stagger comes from the research file: Oryx's translateY percentage, or QMK's y offset.
                let lift: Double =
                    switch stagger {
                    case .oryx: -m.staggerPercent / 100
                    case .qmk: 0.5 - (m.qmkPosition.y - Double(row))
                    }
                let leftX = Double(mirrorCol) + 0.5
                let x = hand == .left ? leftX : width - leftX
                shape = KeyShape(
                    index: index, hand: hand, cluster: .main, row: row, column: col,
                    center: CGPoint(x: x, y: Double(row) + 0.5 - lift),
                    size: CGSize(width: 1, height: 1), rotation: 0, isHomeRow: m.isHomeRow,
                    matrix: matrix, qmkPosition: m.qmkPosition, ledPosition: m.ledPoint)
            } else {
                // Thumbs: 24 outer / 25 inner on the left; 51 outer / 50 inner on the right.
                let isInner = index == 25 || index == 50
                let local = isInner ? innerLocal : outerLocal
                let size = CGSize(width: 1, height: isInner ? 1.35 : 1)
                let off = rotate(local, thumbAngle)
                var c = CGPoint(x: pivot.x + off.x, y: pivot.y + off.y)
                var rot = thumbAngle
                if hand == .right { c.x = width - c.x; rot = -thumbAngle }
                shape = KeyShape(
                    index: index, hand: hand, cluster: .thumb, row: 4, column: isInner ? 1 : 0, center: c, size: size,
                    rotation: rot, isHomeRow: false, matrix: matrix, qmkPosition: m.qmkPosition, ledPosition: m.ledPoint)
            }
            keys.append(shape)
        }
        var anchor: NavigatorAnchor?
        if let side = navigator {
            // Oryx draws the Navigator beside the inner column, between rows 1 and 2.
            let innerX = side == .right ? width - 5.5 - 1.0 : 5.5 + 1.0
            anchor = NavigatorAnchor(hand: side, center: CGPoint(x: innerX, y: 2.0), diameter: 0.95)
        }
        return Self(name: board.displayName, keys: keys, navigator: anchor, halfGap: gap, stagger: stagger)
    }

    /// Key by index.
    public func key(_ index: Int) -> KeyShape { keys[index] }

    /// Bounds of all keys in key units (rotated thumbs included).
    public var bounds: CGRect { keys.map(\.boundingBox).reduce(CGRect.null) { $0.union($1) } }

    /// Nearest key from `index` in a direction, for arrow-key selection. Crosses between halves and into the thumbs.
    public func neighbor(of index: Int, toward direction: Direction) -> Int? {
        let from = keys[index].center
        let d: CGPoint =
            switch direction {
            case .left: CGPoint(x: -1, y: 0)
            case .right: CGPoint(x: 1, y: 0)
            case .up: CGPoint(x: 0, y: -1)
            case .down: CGPoint(x: 0, y: 1)
            }
        var best: (Int, CGFloat)?
        for k in keys where k.index != index {
            let v = CGPoint(x: k.center.x - from.x, y: k.center.y - from.y)
            let along = v.x * d.x + v.y * d.y
            guard along > 0.35 else { continue }
            let perp = abs(v.x * d.y - v.y * d.x)
            guard perp < along * 1.6 + 0.3 else { continue }
            let score = along + perp * 2.2
            if let b = best, score >= b.1 { continue }
            best = (k.index, score)
        }
        return best?.0
    }

    /// Point-space layout.
    /// - Parameters:
    ///   - keySize: side of a 1u keycap in points (the visible cap, not the pitch).
    ///   - spacing: gap between neighbouring caps in points.
    ///   - padding: margin added on every side of the returned ``BoardLayout/size``.
    public func layout(keySize: CGFloat, spacing: CGFloat, padding: CGFloat = 0) -> BoardLayout {
        let pitch = keySize + spacing
        var frames: [BoardLayout.KeyFrame] = keys.map { k in
            BoardLayout.KeyFrame(
                index: k.index, center: CGPoint(x: k.center.x * pitch, y: k.center.y * pitch),
                size: CGSize(width: k.size.width * pitch - spacing, height: k.size.height * pitch - spacing),
                rotation: k.rotation, hand: k.hand)
        }
        let box = frames.map(\.boundingBox).reduce(CGRect.null) { $0.union($1) }
        let dx = padding - box.minX, dy = padding - box.minY
        for i in frames.indices { frames[i].center.x += dx; frames[i].center.y += dy }
        let nav = navigator.map { n in
            BoardLayout.NavigatorFrame(
                hand: n.hand, center: CGPoint(x: n.center.x * pitch + dx, y: n.center.y * pitch + dy),
                diameter: n.diameter * pitch - spacing)
        }
        return BoardLayout(
            keySize: keySize, spacing: spacing, pitch: pitch,
            size: CGSize(width: box.width + padding * 2, height: box.height + padding * 2),
            frames: frames, navigator: nav)
    }

    static func corners(center: CGPoint, size: CGSize, rotation: Double) -> [CGPoint] {
        let r = rotation * .pi / 180, c = cos(r), s = sin(r)
        let hw = size.width / 2, hh = size.height / 2
        return [CGPoint(x: -hw, y: -hh), CGPoint(x: hw, y: -hh), CGPoint(x: hw, y: hh), CGPoint(x: -hw, y: hh)].map { p in
            CGPoint(x: center.x + p.x * c - p.y * s, y: center.y + p.x * s + p.y * c)
        }
    }

    static func box(_ pts: [CGPoint]) -> CGRect {
        let xs = pts.map(\.x), ys = pts.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return .null }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// A board laid out in points. Origin top-left; y down; frames already exclude spacing.
///
/// SwiftUI placement for each key:
/// ```swift
/// ForEach(layout.frames) { f in
///     KeyView(...)
///         .frame(width: f.size.width, height: f.size.height)
///         .rotationEffect(.degrees(f.rotation))
///         .position(f.center)
/// }
/// .frame(width: layout.size.width, height: layout.size.height)
/// ```
public struct BoardLayout: Hashable, Sendable {
    public struct KeyFrame: Identifiable, Hashable, Sendable {
        public var index: Int
        public var id: Int { index }
        /// Centre in points.
        public var center: CGPoint
        /// Cap size in points (spacing already removed).
        public var size: CGSize
        /// Degrees, clockwise positive.
        public var rotation: Double
        public var hand: BoardGeometry.Hand

        /// Rotated corners in points.
        public var corners: [CGPoint] { BoardGeometry.corners(center: center, size: size, rotation: rotation) }
        /// Axis-aligned bounds of the rotated cap.
        public var boundingBox: CGRect { BoardGeometry.box(corners) }

        /// Rotation-aware hit test.
        public func contains(_ p: CGPoint) -> Bool {
            let r = -rotation * .pi / 180
            let dx = p.x - center.x, dy = p.y - center.y
            let x = dx * cos(r) - dy * sin(r), y = dx * sin(r) + dy * cos(r)
            return abs(x) <= size.width / 2 && abs(y) <= size.height / 2
        }
    }

    public struct NavigatorFrame: Hashable, Sendable {
        public var hand: BoardGeometry.Hand
        public var center: CGPoint
        public var diameter: CGFloat
    }

    public var keySize: CGFloat
    public var spacing: CGFloat
    /// keySize + spacing.
    public var pitch: CGFloat
    /// Overall size including padding.
    public var size: CGSize
    public var frames: [KeyFrame]
    public var navigator: NavigatorFrame?

    public func frame(_ index: Int) -> KeyFrame { frames[index] }

    /// Key index under a point, if any.
    public func keyIndex(at point: CGPoint) -> Int? { frames.first { $0.contains(point) }?.index }
}

extension BoardDefinition {
    /// This board's key shapes, with a Navigator anchor on `navigator`'s side.
    /// shortcut: Sextant knows one board, so this is the Voyager builder; a second board brings its own builder
    /// or data-driven shapes (QMK info.json / KLE) here (ADR 0017).
    public func geometry(navigator: BoardGeometry.Hand? = nil) -> BoardGeometry {
        BoardGeometry.voyager(navigator: navigator)
    }
}
