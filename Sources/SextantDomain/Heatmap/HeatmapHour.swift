import Foundation

/// One hour of typing on one layout: key presses by layer id and key index, and how often the keyboard moved onto each
/// layer (ADR 0053). The finest grain the Heatmap keeps: no order, no timing within the hour, and no characters, only
/// positions.
public struct HeatmapHour: Hashable, Sendable {
    /// The hour's start, a whole hour since the reference date (so whole in UTC).
    public var start: Date
    /// Presses by layer id (``Layer/id``), then key index.
    public var presses: [String: [Int: Int]]
    /// How many times the keyboard moved onto each layer, by layer id.
    public var layerEntries: [String: Int]

    public init(start: Date, presses: [String: [Int: Int]] = [:], layerEntries: [String: Int] = [:]) {
        self.start = start
        self.presses = presses
        self.layerEntries = layerEntries
    }

    public static let duration: TimeInterval = 3600

    /// The start of the hour `date` falls in.
    public static func start(of date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / duration).rounded(.down) * duration)
    }

    public var isEmpty: Bool { presses.values.allSatisfy(\.isEmpty) && layerEntries.isEmpty }

    /// Adds another hour's counts to this one's.
    public mutating func add(_ other: Self) {
        for (layer, keys) in other.presses {
            presses[layer, default: [:]].merge(keys, uniquingKeysWith: +)
        }
        layerEntries.merge(other.layerEntries, uniquingKeysWith: +)
    }
}

/// The time ranges the Heatmap shows (spec §8.5).
public enum HeatmapRange: String, CaseIterable, Hashable, Sendable {
    case day, week, month, all

    /// The first hour the range holds at `now`, nil for all of it. A range counts whole hours, the current one included.
    public func start(now: Date) -> Date? {
        let hours: Double =
            switch self {
            case .day: 24
            case .week: 7 * 24
            case .month: 30 * 24
            case .all: 0
            }
        guard hours > 0 else { return nil }
        return HeatmapHour.start(of: now).addingTimeInterval(-(hours - 1) * HeatmapHour.duration)
    }
}
