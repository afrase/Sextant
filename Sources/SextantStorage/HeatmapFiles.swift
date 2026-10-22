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
/// day replaces it. Only the user can open the folder and the files (ADR 0066).
public actor HeatmapFiles: HeatmapStore {
    static let format = 1

    private let root: URL
    private let log = Logger(subsystem: "com.sextant.app", category: "storage")
    /// Each day file's counts added up, by path, with what the file looked like when they were read: windows read the
    /// range again after every write, and a year of files takes most of a second to decode (ADR 0066).
    private var days: [String: (stamp: Stamp, sum: KeyHeatmap)] = [:]
    /// The root was made the user's alone since launch.
    private var rootIsPrivate = false

    public init(root: URL) { self.root = root }

    /// `~/Library/Application Support/Sextant/Heatmap/`, beside the library, not in it.
    public static func defaultRoot() -> URL {
        URL.applicationSupportDirectory.appending(path: "Sextant/Heatmap", directoryHint: .isDirectory)
    }

    public func heatmap(of layoutID: UUID, from start: Date?) throws(HeatmapStoreError) -> KeyHeatmap {
        var heatmap = KeyHeatmap()
        for (day, url) in try files(of: layoutID) {
            guard let start, day < start else {
                heatmap.add(sum(url))
                continue
            }
            // The range starts within this day: only its hours from `start` count.
            guard day.addingTimeInterval(Self.day) > start else { continue }
            for hour in read(url) where hour.start >= start { heatmap.add(hour) }
        }
        return heatmap
    }

    /// The stored hours of a layout from `start` on (all of them when nil), oldest first.
    func hours(of layoutID: UUID, from start: Date?) throws(HeatmapStoreError) -> [HeatmapHour] {
        let inRange = try files(of: layoutID).filter { day, _ in start.map { day.addingTimeInterval(Self.day) > $0 } ?? true }
        return inRange.sorted { $0.day < $1.day }.flatMap { read($0.url) }.filter { hour in start.map { hour.start >= $0 } ?? true }
            .sorted { $0.start < $1.start }
    }

    /// An hour lies in one day file, replaced atomically, so the add is whole or not at all.
    public func add(_ hour: HeatmapHour, to layoutID: UUID) throws(HeatmapStoreError) {
        guard !hour.isEmpty else { return }
        let folder = root.appending(path: layoutID.uuidString, directoryHint: .isDirectory)
        try makeRootPrivate()
        try io { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: Self.privateFolder) }
        let url = folder.appending(path: Self.name(Self.dayStart(hour.start)))
        var byHour = Dictionary(read(url).map { ($0.start, $0) }, uniquingKeysWith: { first, _ in first })
        byHour[hour.start, default: HeatmapHour(start: hour.start)].add(hour)
        try write(Array(byHour.values), to: url)
    }

    public func prune(before date: Date) throws(HeatmapStoreError) {
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        // At launch, so a folder an earlier Sextant made is the user's alone before the next write.
        try makeRootPrivate()
        for layout in try io({ try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) }) {
            guard let id = UUID(uuidString: layout.lastPathComponent) else { continue }
            for (day, url) in try files(of: id) where day < date {
                if day.addingTimeInterval(Self.day) <= date {
                    days[url.path] = nil
                    try io { try FileManager.default.removeItem(at: url) }
                } else {
                    try write(read(url).filter { $0.start >= date }, to: url)
                }
            }
            // A folder left empty would still say recording ran for that layout.
            if try io({ try FileManager.default.contentsOfDirectory(atPath: layout.path).isEmpty }) {
                try io { try FileManager.default.removeItem(at: layout) }
            }
        }
    }

    public func clear(_ layoutID: UUID?) throws(HeatmapStoreError) {
        let target = layoutID.map { root.appending(path: $0.uuidString, directoryHint: .isDirectory) } ?? root
        days = days.filter { !$0.key.hasPrefix(target.path) }
        if layoutID == nil { rootIsPrivate = false }
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        try io { try FileManager.default.removeItem(at: target) }
    }

    // MARK: Files

    private static let day: TimeInterval = 24 * 3600
    /// A folder only the user can open.
    private static var privateFolder: [FileAttributeKey: Any] { [.posixPermissions: 0o700] }
    private static let stampKeys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
    private static let dayStyle = Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day()

    static func dayStart(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / day).rounded(.down) * day)
    }

    static func name(_ day: Date) -> String { "\(day.formatted(dayStyle)).json" }

    /// A layout's day files with the UTC day each holds; other files are left alone.
    private func files(of layoutID: UUID) throws(HeatmapStoreError) -> [(day: Date, url: URL)] {
        let folder = root.appending(path: layoutID.uuidString, directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        let urls = try io { try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(Self.stampKeys)) }
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

    /// What a day file looked like when it was read: a write, or an edit outside Sextant, changes it.
    private struct Stamp: Equatable {
        var modified: Date?
        var size: Int?
    }

    /// A day file's counts added up, read again only when the file has changed since.
    private func sum(_ url: URL) -> KeyHeatmap {
        let values = try? url.resourceValues(forKeys: Self.stampKeys)
        let stamp = Stamp(modified: values?.contentModificationDate, size: values?.fileSize)
        if let cached = days[url.path], cached.stamp == stamp { return cached.sum }
        let sum = KeyHeatmap(read(url))
        days[url.path] = (stamp, sum)
        return sum
    }

    /// The root, and so every layout's folder in it, opens for the user alone, whatever an earlier Sextant made it. A
    /// volume that refuses is logged, not failed: the counts are still worth keeping.
    private func makeRootPrivate() throws(HeatmapStoreError) {
        guard !rootIsPrivate else { return }
        try io { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: Self.privateFolder) }
        restrict(root, to: 0o700)
        rootIsPrivate = true
    }

    /// Sets an item's permissions, logging a refusal: a write that landed must not fail over them, or it would be retried
    /// and counted twice.
    private func restrict(_ url: URL, to permissions: Int) {
        do {
            try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        } catch {
            log.error("Couldn't restrict heatmap permissions: \(error.localizedDescription, privacy: .public)")
        }
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
        // Damage or an edit: a count below 1 is left out, like a key that isn't a number, and one no hour could reach
        // is held to the limit, so sums stay far from overflowing.
        let count = { (n: Int) in n >= 1 ? min(n, HeatmapHour.countLimit) : nil }
        return file.hours.map { hour in
            let presses = hour.presses.mapValues { keys in
                Dictionary(
                    keys.compactMap { key, n in Int(key).flatMap { index in count(n).map { (index, $0) } } },
                    uniquingKeysWith: HeatmapHour.sum)
            }
            return HeatmapHour(start: hour.start, presses: presses, layerEntries: (hour.layers ?? [:]).compactMapValues(count))
        }
    }

    private func write(_ hours: [HeatmapHour], to url: URL) throws(HeatmapStoreError) {
        days[url.path] = nil
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
        restrict(url, to: 0o600)
    }

    private func io<T>(_ body: () throws -> T) throws(HeatmapStoreError) -> T {
        do { return try body() } catch { throw .io(error.localizedDescription) }
    }
}
