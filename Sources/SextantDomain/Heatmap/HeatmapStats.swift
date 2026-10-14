import Foundation

/// What the Heatmap inspector shows about a range (spec §8.5): layer share, hand balance, presses per finger, the busiest
/// keys and how often each layer was reached. Only the layout's own layers count: presses on a layer since deleted stay
/// stored but aren't shown.
public struct HeatmapStats: Hashable, Sendable {
    /// One layer's presses and its share of all of them.
    public struct LayerShare: Hashable, Sendable {
        public var layer: Int
        public var presses: Int
        /// 0...1 of ``HeatmapStats/total``.
        public var share: Double
    }

    /// Presses by one finger of one hand.
    public struct FingerCount: Hashable, Sendable {
        public var hand: BoardDefinition.Hand
        public var finger: BoardDefinition.Finger
        public var presses: Int
    }

    /// One key on one layer.
    public struct KeyCount: Hashable, Sendable {
        public var layer: Int
        public var index: Int
        public var presses: Int
    }

    /// How many times the keyboard moved onto a layer above the base.
    public struct LayerReach: Hashable, Sendable {
        public var layer: Int
        public var times: Int
    }

    public var total: Int
    /// Every layer of the layout, in its order.
    public var layers: [LayerShare]
    public var left: Int
    public var right: Int
    /// The left hand from pinky to thumb, then the right from thumb to pinky, as the hands lie on the board.
    public var fingers: [FingerCount]
    /// The busiest keys of every layer, busiest first.
    public var top: [KeyCount]
    /// Layers above the base the keyboard was moved onto, in layer order; empty when none was.
    public var reached: [LayerReach]

    /// - Parameter top: how many busiest keys to list (spec §8.5: 8).
    public init(_ heatmap: KeyHeatmap, layout: KeyboardLayout, board: BoardDefinition = .voyager, top: Int = 8) {
        let ids = layout.layers.map(\.id)
        let totals = ids.map { heatmap.total(layer: $0) }
        let total = totals.reduce(0, +)
        self.total = total
        layers = totals.enumerated().map {
            LayerShare(layer: $0.offset, presses: $0.element, share: total > 0 ? Double($0.element) / Double(total) : 0)
        }
        var byKey: [Int: Int] = [:]
        for id in ids { byKey.merge(heatmap.presses[id] ?? [:], uniquingKeysWith: +) }
        var byFinger: [BoardDefinition.Hand: [BoardDefinition.Finger: Int]] = [:]
        for key in board.keys { byFinger[key.hand, default: [:]][key.finger, default: 0] += byKey[key.index] ?? 0 }
        left = byFinger[.left]?.values.reduce(0, +) ?? 0
        right = byFinger[.right]?.values.reduce(0, +) ?? 0
        let order = BoardDefinition.Finger.allCases
        fingers =
            order.map { FingerCount(hand: .left, finger: $0, presses: byFinger[.left]?[$0] ?? 0) }
            + order.reversed().map { FingerCount(hand: .right, finger: $0, presses: byFinger[.right]?[$0] ?? 0) }
        let layerOf = Dictionary(ids.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        self.top = heatmap.top(top, layers: ids).compactMap { entry in
            layerOf[entry.layer].map { KeyCount(layer: $0, index: entry.index, presses: entry.count) }
        }
        reached = ids.enumerated().dropFirst().compactMap { layer, id in
            let times = heatmap.layerEntries[id] ?? 0
            return times > 0 ? LayerReach(layer: layer, times: times) : nil
        }
    }
}
