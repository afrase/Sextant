import Foundation

/// Key presses over a range of hours, by layer id and key index, with the layer entries (spec §8.5). Seeded from
/// PrototypeKit's sample heatmap, keyed by layer id so a layer keeps its counts when layers are reordered.
public struct KeyHeatmap: Hashable, Sendable {
    /// One key's presses on one layer.
    public struct Entry: Hashable, Sendable {
        public var layer: String
        public var index: Int
        public var count: Int
    }

    /// Presses by layer id, then key index.
    public private(set) var presses: [String: [Int: Int]] = [:]
    /// Moves onto each layer, by layer id.
    public private(set) var layerEntries: [String: Int] = [:]

    public init() {}

    public init(_ hours: some Sequence<HeatmapHour>) {
        for hour in hours { add(hour) }
    }

    public mutating func add(_ hour: HeatmapHour) {
        for (layer, keys) in hour.presses where !keys.isEmpty {
            presses[layer, default: [:]].merge(keys, uniquingKeysWith: HeatmapHour.sum)
        }
        layerEntries.merge(hour.layerEntries, uniquingKeysWith: HeatmapHour.sum)
    }

    /// Adds another range's counts to this one's.
    public mutating func add(_ other: Self) {
        for (layer, keys) in other.presses where !keys.isEmpty {
            presses[layer, default: [:]].merge(keys, uniquingKeysWith: HeatmapHour.sum)
        }
        layerEntries.merge(other.layerEntries, uniquingKeysWith: HeatmapHour.sum)
    }

    public func count(layer: String, index: Int) -> Int { presses[layer]?[index] ?? 0 }

    /// Presses on one layer, or on every layer when `layer` is nil.
    public func total(layer: String? = nil) -> Int {
        guard let layer else { return presses.values.reduce(0) { HeatmapHour.sum($0, $1.values.reduce(0, HeatmapHour.sum)) } }
        return presses[layer]?.values.reduce(0, HeatmapHour.sum) ?? 0
    }

    /// The busiest key's presses on a layer.
    public func maxCount(layer: String) -> Int { presses[layer]?.values.max() ?? 0 }

    /// 0...1 against the layer's busiest key, on a log scale so the long tail of rarely used keys still shows.
    public func intensity(layer: String, index: Int) -> Double {
        let most = Double(maxCount(layer: layer)), count = Double(count(layer: layer, index: index))
        guard most > 0, count > 0 else { return 0 }
        return log1p(count) / log1p(most)
    }

    /// The `n` busiest keys of the given layers (every layer when nil), busiest first; ties by layer order, then index.
    public func top(_ n: Int, layers: [String]? = nil) -> [Entry] {
        let order = layers ?? presses.keys.sorted()
        let entries = order.enumerated().flatMap { rank, layer in
            (presses[layer] ?? [:]).filter { $0.value > 0 }.map { (rank: rank, entry: Entry(layer: layer, index: $0.key, count: $0.value)) }
        }
        let sorted = entries.sorted { a, b in
            if a.entry.count != b.entry.count { return a.entry.count > b.entry.count }
            return (a.rank, a.entry.index) < (b.rank, b.entry.index)
        }
        return sorted.prefix(max(n, 0)).map(\.entry)
    }
}
