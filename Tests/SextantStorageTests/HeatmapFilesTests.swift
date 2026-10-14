import Foundation
import SextantApplication
import SextantDomain
import Testing

@testable import SextantStorage

/// Contract tests for the Heatmap's day files (ADR 0053), against a temporary folder.
struct HeatmapFilesTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "sextant-heatmap-\(UUID().uuidString)", directoryHint: .isDirectory)
    let files: HeatmapFiles
    let layout = UUID()
    /// 2026-10-15 12:00 UTC.
    let noon = Date(timeIntervalSinceReferenceDate: 813_758_400)

    init() { files = HeatmapFiles(root: root) }

    func hour(_ offset: Int, _ presses: [Int: Int], layer: String = "main", entries: [String: Int] = [:]) -> HeatmapHour {
        HeatmapHour(start: noon.addingTimeInterval(Double(offset) * 3600), presses: [layer: presses], layerEntries: entries)
    }

    func dayFiles(_ id: UUID? = nil) -> [String] {
        let folder = root.appending(path: (id ?? layout).uuidString)
        return ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    @Test func writesAndReadsHoursByDay() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        // Noon, 23:00 and the next day's 01:00, UTC.
        try await files.add([hour(0, [1: 2]), hour(11, [2: 1], entries: ["sym": 3]), hour(13, [3: 5])], to: layout)
        #expect(dayFiles() == ["2026-10-15.json", "2026-10-16.json"])
        let all = try await files.hours(of: layout, from: nil)
        #expect(all == [hour(0, [1: 2]), hour(11, [2: 1], entries: ["sym": 3]), hour(13, [3: 5])])
        #expect(try await files.hours(of: layout, from: noon.addingTimeInterval(3600)).map(\.start) == [all[1].start, all[2].start])
        #expect(try await files.hours(of: UUID(), from: nil).isEmpty, "another layout has none")
    }

    @Test func addingMergesIntoTheStoredHour() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try await files.add([hour(0, [1: 2], entries: ["sym": 1])], to: layout)
        try await files.add([hour(0, [1: 3, 4: 1], entries: ["sym": 2]), hour(1, [1: 1])], to: layout)
        let hours = try await files.hours(of: layout, from: nil)
        #expect(hours == [hour(0, [1: 5, 4: 1], entries: ["sym": 3]), hour(1, [1: 1])])
    }

    /// Only hours, layers, key positions and counts: no key order, no time finer than the hour, no characters.
    @Test func aFileHoldsOnlyHourlyCounts() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try await files.add([hour(0, [13: 2], entries: ["sym": 1])], to: layout)
        let data = try Data(contentsOf: root.appending(path: "\(layout.uuidString)/2026-10-15.json"))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["format", "hours"])
        let hours = try #require(object["hours"] as? [[String: Any]])
        #expect(Set(hours[0].keys) == ["start", "presses", "layers"])
        #expect(hours[0]["start"] as? String == "2026-10-15T12:00:00Z")
        #expect(hours[0]["presses"] as? [String: [String: Int]] == ["main": ["13": 2]])
    }

    @Test func pruneDropsOldDaysAndTrimsTheDayItCuts() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let other = UUID()
        try await files.add([hour(-48, [1: 1]), hour(-1, [1: 1]), hour(0, [1: 1]), hour(2, [1: 1])], to: layout)
        try await files.add([hour(-48, [1: 1])], to: other)
        try await files.prune(before: noon)
        #expect(try await files.hours(of: layout, from: nil).map(\.start) == [noon, noon.addingTimeInterval(7200)])
        #expect(dayFiles() == ["2026-10-15.json"])
        #expect(dayFiles(other).isEmpty, "every layout is pruned")
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: root.path) == [layout.uuidString],
            "a layout with nothing left keeps no folder: it would say recording ran for it")
        try await files.prune(before: noon.addingTimeInterval(-3600 * 24 * 365))
        #expect(try await files.hours(of: layout, from: nil).count == 2)
    }

    @Test func clearsOneLayoutOrAll() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let other = UUID()
        try await files.add([hour(0, [1: 1])], to: layout)
        try await files.add([hour(0, [1: 1])], to: other)
        try await files.clear(layout)
        #expect(try await files.hours(of: layout, from: nil).isEmpty)
        #expect(try await files.hours(of: other, from: nil).count == 1)
        try await files.clear(nil)
        #expect(!FileManager.default.fileExists(atPath: root.path))
        try await files.clear(nil)
        try await files.prune(before: noon)
    }

    @Test func aDamagedFileReadsAsEmptyAndIsReplaced() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try await files.add([hour(0, [1: 1]), hour(24, [1: 1])], to: layout)
        let url = root.appending(path: "\(layout.uuidString)/2026-10-15.json")
        try Data("{\"format\": 1, \"hou".utf8).write(to: url)
        #expect(try await files.hours(of: layout, from: nil) == [hour(24, [1: 1])], "the other day still reads")
        try await files.add([hour(1, [2: 4])], to: layout)
        #expect(try await files.hours(of: layout, from: nil) == [hour(1, [2: 4]), hour(24, [1: 1])])
        // A newer Sextant's file and files that aren't days are left out.
        try Data("{\"format\": 2, \"hours\": []}".utf8).write(to: url)
        try Data("x".utf8).write(to: root.appending(path: "\(layout.uuidString)/notes.json"))
        #expect(try await files.hours(of: layout, from: nil) == [hour(24, [1: 1])])
    }

    /// Counts a file can't have come from typing (damaged or edited) neither crash a read, a merge or a sum, nor show as
    /// negative: below 1 is left out, and past the limit is held to it.
    @Test func countsOutOfRangeAreHeldOrLeftOut() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try await files.add([hour(0, [1: 1])], to: layout)
        let url = root.appending(path: "\(layout.uuidString)/2026-10-15.json")
        let file = """
            {"format": 1, "hours": [{"start": "2026-10-15T12:00:00Z",
              "presses": {"main": {"1": \(Int.max), "01": 1, "2": -500, "3": 0, "4": 3}}, "layers": {"sym": -7, "fn": \(Int.max)}}]}
            """
        try Data(file.utf8).write(to: url)
        let limit = HeatmapHour.countLimit
        let read = try await files.hours(of: layout, from: nil)
        #expect(read == [hour(0, [1: limit + 1, 4: 3], entries: ["fn": limit])], "\"1\" and \"01\" are the same key")
        // The next minute's write merges into it.
        try await files.add([hour(0, [1: .max, 4: 1])], to: layout)
        #expect(try await files.hours(of: layout, from: nil) == [hour(0, [1: limit, 4: 4], entries: ["fn": limit])])
    }
}

extension HeatmapFiles {
    /// Adds several hours, one at a time as the recorder does.
    fileprivate func add(_ hours: [HeatmapHour], to layoutID: UUID) throws(HeatmapStoreError) {
        for hour in hours { try add(hour, to: layoutID) }
    }
}
