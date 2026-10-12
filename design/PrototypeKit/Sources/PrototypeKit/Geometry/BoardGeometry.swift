import Foundation
import CoreGraphics

/// Physical key positions for a board, in **key units** (1u = key pitch: key plus gap), y growing downward.
///
/// `BoardGeometry.voyager` is built from `Resources/voyager-geometry.json` (rows, columns, column stagger,
/// thumb rotation, QMK and LED coordinates, matrix positions) and calibrated against Oryx's own render
/// (`docs/oryx-ui/01-layout-readonly-main.jpg`, kept outside the repo in the reference folder):
/// - Column stagger: columns 2 and 4 of each half are raised 0.15u and the middle-finger column 0.30u
///   (Oryx's `translateY(-15% / -30%)`); `.qmk` uses QMK `keyboard.json`'s 0.25u / 0.5u instead.
/// - Thumbs: per half, a 1u key (24 / 51) and a taller 1u × 1.35u key (25 / 50) sharing a top edge,
///   rotated +30° (left) / −30° (right) about the cluster centre. The research JSON lists both thumbs
///   square; Oryx actually draws the inner one taller, which this geometry follows.
/// - Halves: 4.9u apart by default (Oryx proportions), adjustable with `halfGap`.
///
/// Use ``layout(keySize:spacing:padding:)`` or ``layout(fitting:spacingRatio:padding:)`` to get point frames.
public struct BoardGeometry: Hashable, Sendable {
    /// Keys on a ZSA Voyager.
    public static let voyagerKeyCount = 52

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

    /// The default Voyager geometry (Oryx stagger, 4.9u half gap, Navigator anchor on the right).
    public static let voyager: BoardGeometry = .voyager()

    /// Builds Voyager geometry.
    /// - Parameters:
    ///   - stagger: column-stagger profile.
    ///   - halfGap: space between the halves' inner edges in key units. Values below 2.4 are clamped so the thumb clusters can't overlap.
    ///   - navigator: side carrying a Navigator anchor, or nil.
    public static func voyager(stagger: Stagger = .oryx, halfGap: Double = 4.9, navigator: Hand? = .right) -> BoardGeometry {
        let gap = max(2.4, halfGap)
        let width = 12 + gap
        let meta = VoyagerGeometryFile.shared
        var keys: [KeyShape] = []
        let raise: [Double] = stagger == .oryx ? [0, 0, 0.15, 0.30, 0.15, 0] : [0, 0, 0.25, 0.5, 0.25, 0]
        // Thumb cluster (left half; the right half mirrors it). Calibrated to Oryx's render.
        let pivot = CGPoint(x: 6.04, y: 5.18)
        let thumbAngle = 30.0
        let outerLocal = CGPoint(x: -0.5, y: 0)        // key 24: 1u × 1u
        let innerLocal = CGPoint(x: 0.5, y: 0.175)     // key 25: 1u × 1.35u, tops aligned
        func rotate(_ p: CGPoint, _ deg: Double) -> CGPoint {
            let r = deg * .pi / 180
            return CGPoint(x: p.x * cos(r) - p.y * sin(r), y: p.x * sin(r) + p.y * cos(r))
        }
        for index in 0..<voyagerKeyCount {
            let m = meta.keys[index]
            let hand: Hand = index <= 25 ? .left : .right
            var shape: KeyShape
            if (0...23).contains(index) || (26...49).contains(index) {
                let local = hand == .left ? index : index - 26
                let row = local / 6, col = local % 6
                // Left column c and right column (5 - c) mirror each other.
                let mirrorCol = hand == .left ? col : 5 - col
                // Stagger comes from the research file: Oryx's translateY percentage, or QMK's y offset.
                let lift: Double = switch stagger {
                case .oryx: m?.translateYPercent.map { -$0 / 100 } ?? raise[mirrorCol]
                case .qmk: m?.qmk.map { 0.5 - ($0.y - Double(row)) } ?? raise[mirrorCol]
                }
                let leftX = Double(mirrorCol) + 0.5
                let x = hand == .left ? leftX : width - leftX
                shape = KeyShape(index: index, hand: hand, cluster: .main, row: row, column: col,
                                 center: CGPoint(x: x, y: Double(row) + 0.5 - lift),
                                 size: CGSize(width: 1, height: 1), rotation: 0, isHomeRow: m?.isOnHomeRow ?? (row == 2 && col != (hand == .left ? 0 : 5)),
                                 matrix: m?.matrix, qmkPosition: m?.qmk, ledPosition: m?.led)
            } else {
                // Thumbs: 24 outer / 25 inner on the left; 51 outer / 50 inner on the right.
                let isInner = index == 25 || index == 50
                let local = isInner ? innerLocal : outerLocal
                let size = CGSize(width: 1, height: isInner ? 1.35 : 1)
                let off = rotate(local, thumbAngle)
                var c = CGPoint(x: pivot.x + off.x, y: pivot.y + off.y)
                var rot = thumbAngle
                if hand == .right { c.x = width - c.x; rot = -thumbAngle }
                shape = KeyShape(index: index, hand: hand, cluster: .thumb, row: 4, column: isInner ? 1 : 0, center: c, size: size,
                                 rotation: rot, isHomeRow: false, matrix: m?.matrix, qmkPosition: m?.qmk, ledPosition: m?.led)
            }
            keys.append(shape)
        }
        var anchor: NavigatorAnchor?
        if let side = navigator {
            // Oryx draws the Navigator beside the inner column, between rows 1 and 2.
            let innerX = side == .right ? width - 5.5 - 1.0 : 5.5 + 1.0
            anchor = NavigatorAnchor(hand: side, center: CGPoint(x: innerX, y: 2.0), diameter: 0.95)
        }
        return BoardGeometry(name: "ZSA Voyager", keys: keys, navigator: anchor, halfGap: gap, stagger: stagger)
    }

    /// Key by index.
    public func key(_ index: Int) -> KeyShape { keys[index] }

    /// Keys on one half.
    public func keys(on hand: Hand) -> [KeyShape] { keys.filter { $0.hand == hand } }

    /// Bounds of all keys in key units (rotated thumbs included).
    public var bounds: CGRect { keys.map(\.boundingBox).reduce(CGRect.null) { $0.union($1) } }

    /// Bounds of one half in key units.
    public func bounds(of hand: Hand) -> CGRect { keys(on: hand).map(\.boundingBox).reduce(CGRect.null) { $0.union($1) } }

    /// Nearest key from `index` in a direction, for arrow-key selection. Crosses between halves and into the thumbs.
    public func neighbor(of index: Int, toward direction: Direction) -> Int? {
        let from = keys[index].center
        let d: CGPoint = switch direction {
        case .left: CGPoint(x: -1, y: 0)
        case .right: CGPoint(x: 1, y: 0)
        case .up: CGPoint(x: 0, y: -1)
        case .down: CGPoint(x: 0, y: 1)
        }
        var best: (Int, Double)?
        for k in keys where k.index != index {
            let v = CGPoint(x: k.center.x - from.x, y: k.center.y - from.y)
            let along = v.x * d.x + v.y * d.y
            guard along > 0.35 else { continue }
            let perp = abs(v.x * d.y - v.y * d.x)
            guard perp < along * 1.6 + 0.3 else { continue }
            let score = along + perp * 2.2
            if best == nil || score < best!.1 { best = (k.index, score) }
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
            BoardLayout.KeyFrame(index: k.index, center: CGPoint(x: k.center.x * pitch, y: k.center.y * pitch),
                                 size: CGSize(width: k.size.width * pitch - spacing, height: k.size.height * pitch - spacing),
                                 rotation: k.rotation, hand: k.hand)
        }
        let box = frames.map(\.boundingBox).reduce(CGRect.null) { $0.union($1) }
        let dx = padding - box.minX, dy = padding - box.minY
        for i in frames.indices { frames[i].center.x += dx; frames[i].center.y += dy }
        let nav = navigator.map { n in
            BoardLayout.NavigatorFrame(hand: n.hand, center: CGPoint(x: n.center.x * pitch + dx, y: n.center.y * pitch + dy),
                                       diameter: n.diameter * pitch - spacing)
        }
        return BoardLayout(keySize: keySize, spacing: spacing, pitch: pitch,
                           size: CGSize(width: box.width + padding * 2, height: box.height + padding * 2),
                           frames: frames, navigator: nav)
    }

    /// The largest layout that fits `size`, with `spacing = keySize * spacingRatio`.
    public func layout(fitting size: CGSize, spacingRatio: CGFloat = 0.1, padding: CGFloat = 0) -> BoardLayout {
        let unit = layout(keySize: 1, spacing: spacingRatio, padding: 0).size
        let scale = min((size.width - padding * 2) / unit.width, (size.height - padding * 2) / unit.height)
        var l = layout(keySize: max(1, scale), spacing: max(0, scale * spacingRatio), padding: padding)
        // Centre inside the requested size.
        let extraX = (size.width - l.size.width) / 2, extraY = (size.height - l.size.height) / 2
        for i in l.frames.indices { l.frames[i].center.x += extraX; l.frames[i].center.y += extraY }
        if var n = l.navigator { n.center.x += extraX; n.center.y += extraY; l.navigator = n }
        l.size = size
        return l
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
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
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

        /// Unrotated rect centred on ``center``.
        public var rect: CGRect { CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height) }
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

    /// Bounds of every cap.
    public var keysBounds: CGRect { frames.map(\.boundingBox).reduce(CGRect.null) { $0.union($1) } }

    /// Bounds of one half's caps.
    public func bounds(of hand: BoardGeometry.Hand) -> CGRect {
        frames.filter { $0.hand == hand }.map(\.boundingBox).reduce(CGRect.null) { $0.union($1) }
    }

    /// Key index under a point, if any.
    public func keyIndex(at point: CGPoint) -> Int? { frames.first { $0.contains(point) }?.index }
}

// MARK: - voyager-geometry.json

/// Per-key metadata read from the bundled research file.
struct VoyagerGeometryFile: Sendable {
    struct KeyMeta: Sendable {
        var translateYPercent: Double?
        var isOnHomeRow: Bool?
        var matrix: BoardGeometry.MatrixPosition?
        var qmk: CGPoint?
        var led: CGPoint?
    }

    var keys: [KeyMeta?]

    static let shared: VoyagerGeometryFile = {
        guard let data = try? PrototypeResources.data("voyager-geometry"),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["keys"] as? [[String: Any]] else {
            return VoyagerGeometryFile(keys: Array(repeating: nil, count: BoardGeometry.voyagerKeyCount))
        }
        var keys = [KeyMeta?](repeating: nil, count: BoardGeometry.voyagerKeyCount)
        for k in list {
            guard let i = k["index"] as? Int, keys.indices.contains(i) else { continue }
            let oryx = k["oryxRender"] as? [String: Any]
            let qmk = k["qmk"] as? [String: Any]
            let led = k["led"] as? [String: Any]
            let hid = k["webhidMatrix"] as? [String: Any]
            keys[i] = KeyMeta(
                translateYPercent: (oryx?["translateYPercent"] as? NSNumber)?.doubleValue,
                isOnHomeRow: k["isOnHomeRow"] as? Bool,
                matrix: (hid?["row"] as? Int).flatMap { r in (hid?["col"] as? Int).map { BoardGeometry.MatrixPosition(row: r, column: $0) } },
                qmk: (qmk?["x"] as? NSNumber).flatMap { x in (qmk?["y"] as? NSNumber).map { CGPoint(x: x.doubleValue, y: $0.doubleValue) } },
                led: (led?["x"] as? NSNumber).flatMap { x in (led?["y"] as? NSNumber).map { CGPoint(x: x.doubleValue, y: $0.doubleValue) } })
        }
        return VoyagerGeometryFile(keys: keys)
    }()
}
