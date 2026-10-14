import Foundation
import SextantApplication
import SextantDomain
import os

/// The Heatmap's hourly counts as small JSON files, one per layout and UTC day, outside the `.sextant` packages so
/// exports, duplicates and revisions never carry typing data (ADR 0053).
///
/// ```
/// <root>/<layout id>/<yyyy-MM-dd>.json   {"format": 1, "hours": [{"start", "presses": {layer id: {key: n}}, "layers": {layer id: n}}]}
/// ```
///
/// Each write replaces a whole file atomically. A file that can't be read counts as empty, and the next write for its
/// day replaces it.
public actor HeatmapFiles: HeatmapStore {
    static let format = 1

    private let root: URL
    private let log = Logger(subsystem: "com.sextant.app", category: "storage")

    public init(root: URL) { self.root = root }

    /// `~/Library/Application Support/Sextant/Heatmap/`, beside the library, not in it.
    public static func defaultRoot() -> URL {
        URL.applicationSupportDirectory.appending(path: "Sextant/Heatmap", directoryHint: .isDirectory)
    }

    public func hours(of layoutID: UUID, from start: Date?) throws(HeatmapStoreError) -> [HeatmapHour] {
        let days = try files(of: layoutID).filter { day, _ in start.map { day.addingTimeInterval(Self.day) > $0 } ?? true }
        return days.sorted { $0.day < $1.day }.flatMap { read($0.url) }.filter { hour in start.map { hour.start >= $0 } ?? true }
            .sorted { $0.start < $1.start }
    }

    public func add(_ hours: [HeatmapHour], to layoutID: UUID) throws(HeatmapStoreError) {
        let folder = root.appending(path: layoutID.uuidString, directoryHint: .isDirectory)
        try io { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        for (day, added) in Dictionary(grouping: hours.filter { !$0.isEmpty }, by: { Self.dayStart($0.start) }) {
            let url = folder.appending(path: Self.name(day))
            var byHour = Dictionary(read(url).map { ($0.start, $0) }, uniquingKeysWith: { first, _ in first })
            for hour in added { byHour[hour.start, default: HeatmapHour(start: hour.start)].add(hour) }
            try write(Array(byHour.values), to: url)
        }
    }

    public func prune(before date: Date) throws(HeatmapStoreError) {
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        for layout in try io({ try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) }) {
            guard let id = UUID(uuidString: layout.lastPathComponent) else { continue }
            for (day, url) in try files(of: id) where day < date {
                if day.addingTimeInterval(Self.day) <= date {
                    try io { try FileManager.default.removeItem(at: url) }
                } else {
                    try write(read(url).filter { $0.start >= date }, to: url)
                }
            }
        }
    }

    public func clear(_ layoutID: UUID?) throws(HeatmapStoreError) {
        let target = layoutID.map { root.appending(path: $0.uuidString, directoryHint: .isDirectory) } ?? root
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        try io { try FileManager.default.removeItem(at: target) }
    }

    // MARK: Files

    private static let day: TimeInterval = 24 * 3600
    private static let dayStyle = Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day()

    static func dayStart(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / day).rounded(.down) * day)
    }

    static func name(_ day: Date) -> String { "\(day.formatted(dayStyle)).json" }

    /// A layout's day files with the UTC day each holds; other files are left alone.
    private func files(of layoutID: UUID) throws(HeatmapStoreError) -> [(day: Date, url: URL)] {
        let folder = root.appending(path: layoutID.uuidString, directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        let urls = try io { try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) }
        return urls.compactMap { url in
            guard url.pathExtension == "json", let day = try? Date(url.deletingPathExtension().lastPathComponent, strategy: Self.dayStyle)
            else { return nil }
            return (day, url)
        }
    }

    private struct DayFile: Codable {
        struct Hour: Codable {
            var start: Date
            /// Layer id, then key index as text (JSON object keys are strings).
            var presses: [String: [String: Int]]
            var layers: [String: Int]?
        }
        var format: Int
        var hours: [Hour]
    }

    /// A day file's hours; none when it is missing, damaged or from a newer Sextant.
    private func read(_ url: URL) -> [HeatmapHour] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(DayFile.self, from: data), file.format <= Self.format else {
            log.error("Skipping unreadable heatmap file \(url.lastPathComponent, privacy: .public)")
            return []
        }
        return file.hours.map { hour in
            let presses = hour.presses.mapValues { keys in
                Dictionary(keys.compactMap { key, count in Int(key).map { ($0, count) } }, uniquingKeysWith: +)
            }
            return HeatmapHour(start: hour.start, presses: presses, layerEntries: hour.layers ?? [:])
        }
    }

    private func write(_ hours: [HeatmapHour], to url: URL) throws(HeatmapStoreError) {
        let kept = hours.filter { !$0.isEmpty }.sorted { $0.start < $1.start }
        guard !kept.isEmpty else {
            try io { if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) } }
            return
        }
        let file = DayFile(
            format: Self.format,
            hours: kept.map { hour in
                DayFile.Hour(
                    start: hour.start,
                    presses: hour.presses.mapValues { Dictionary(uniqueKeysWithValues: $0.map { ("\($0.key)", $0.value) }) },
                    layers: hour.layerEntries.isEmpty ? nil : hour.layerEntries)
            })
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data: Data
        do { data = try encoder.encode(file) } catch { throw .io(String(describing: error)) }
        try io { try data.write(to: url, options: .atomic) }
    }

    private func io<T>(_ body: () throws -> T) throws(HeatmapStoreError) -> T {
        do { return try body() } catch { throw .io(error.localizedDescription) }
    }
}
