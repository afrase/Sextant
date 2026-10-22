import Foundation
import Testing

@testable import SextantDomain

/// The Heatmap's domain (spec §8.5, ADR 0053): hourly counts, their totals and log intensity, the inspector's stats, the
/// finger table, the exports and the heat ramp. Counts are built in code on the user's layout.
struct HeatmapTests {
    let layout: KeyboardLayout
    let main: String, symNum: String, brdSys: String
    let noon = Date(timeIntervalSinceReferenceDate: 813_758_400)  // a whole hour

    init() throws {
        layout = try Fixtures.layout()
        (main, symNum, brdSys) = (layout.layers[0].id, layout.layers[1].id, layout.layers[2].id)
    }

    /// Main: 300 presses of Space (51), 100 of ⏎ (24), 20 of A (13), 1 of = (0); Sym+Num: 50 of key 16; Brd+Sys entered
    /// 7 times.
    func sample() -> KeyHeatmap {
        KeyHeatmap([
            HeatmapHour(start: noon, presses: [main: [51: 200, 24: 100, 0: 1], symNum: [16: 50]], layerEntries: [brdSys: 3]),
            HeatmapHour(start: noon.addingTimeInterval(3600), presses: [main: [51: 100, 13: 20]], layerEntries: [brdSys: 4]),
        ])
    }

    // MARK: Hours and ranges

    @Test func hoursStartOnTheHour() {
        let date = noon.addingTimeInterval(59 * 60 + 59.9)
        #expect(HeatmapHour.start(of: date) == noon)
        #expect(HeatmapHour.start(of: noon) == noon)
        #expect(HeatmapHour.start(of: noon.addingTimeInterval(-0.1)) == noon.addingTimeInterval(-3600))
    }

    @Test func rangesCountWholeHoursIncludingTheCurrentOne() {
        let now = noon.addingTimeInterval(1800)
        #expect(HeatmapRange.day.start(now: now) == noon.addingTimeInterval(-23 * 3600))
        #expect(HeatmapRange.week.start(now: now) == noon.addingTimeInterval(-(7 * 24 - 1) * 3600))
        #expect(HeatmapRange.month.start(now: now) == noon.addingTimeInterval(-(30 * 24 - 1) * 3600))
        #expect(HeatmapRange.all.start(now: now) == nil)
    }

    @Test func hoursAddUp() {
        var hour = HeatmapHour(start: noon, presses: [main: [1: 2]])
        hour.add(HeatmapHour(start: noon, presses: [main: [1: 3, 2: 1], symNum: [5: 1]], layerEntries: [symNum: 1]))
        #expect(hour.presses == [main: [1: 5, 2: 1], symNum: [5: 1]])
        #expect(hour.layerEntries == [symNum: 1])
        #expect(!hour.isEmpty && HeatmapHour(start: noon).isEmpty)
        #expect(hour.total == 7 && HeatmapHour(start: noon, layerEntries: [symNum: 2]).total == 0, "presses, not moves")
    }

    @Test func heatmapsAddUp() {
        var heat = KeyHeatmap([HeatmapHour(start: noon, presses: [main: [1: 2]], layerEntries: [symNum: 1])])
        heat.add(sample())
        var expected = sample()
        expected.add(HeatmapHour(start: noon, presses: [main: [1: 2]], layerEntries: [symNum: 1]))
        #expect(heat == expected && heat.total() == 473 && heat.layerEntries == [symNum: 1, brdSys: 7])
    }

    // MARK: Counts

    @Test func countsAndTotalsByLayerID() {
        let heat = sample()
        #expect(heat.count(layer: main, index: 51) == 300)
        #expect(heat.count(layer: main, index: 50) == 0)
        #expect(heat.count(layer: "gone", index: 51) == 0)
        #expect(heat.total(layer: main) == 421)
        #expect(heat.total() == 471)
        #expect(heat.maxCount(layer: main) == 300)
        #expect(heat.layerEntries[brdSys] == 7)
        #expect(KeyHeatmap().total() == 0)
    }

    @Test func intensityIsLogScaledAgainstTheLayersBusiestKey() {
        let heat = sample()
        #expect(heat.intensity(layer: main, index: 51) == 1)
        #expect(heat.intensity(layer: main, index: 50) == 0)
        #expect(heat.intensity(layer: symNum, index: 16) == 1, "each layer against its own busiest key")
        let enter = heat.intensity(layer: main, index: 24), equals = heat.intensity(layer: main, index: 0)
        #expect(abs(enter - log1p(100) / log1p(300)) < 1e-12)
        #expect(0 < equals && equals < enter && enter < 1)
        #expect(enter > 100.0 / 300, "a log scale lifts the long tail")
    }

    @Test func topKeysAreBusiestFirstThenInLayerOrder() {
        let heat = KeyHeatmap([HeatmapHour(start: noon, presses: [symNum: [3: 5, 1: 9], main: [7: 5, 2: 1]])])
        let top = heat.top(3, layers: [main, symNum])
        #expect(top.map(\.count) == [9, 5, 5])
        #expect(top.map(\.layer) == [symNum, main, symNum], "a tie goes to the lower layer")
        #expect(heat.top(0).isEmpty && heat.top(10).count == 4)
    }

    // MARK: Stats

    @Test func statsOnTheUsersLayout() {
        let stats = HeatmapStats(sample(), layout: layout)
        #expect(stats.total == 471)
        #expect(stats.layers.map(\.presses) == [421, 50, 0])
        #expect(abs(stats.layers.map(\.share).reduce(0, +) - 1) < 1e-9)
        // Left: ⏎ (24, thumb), A (13, pinky), = (0, pinky), key 16 (F, index). Right: Space (51, thumb).
        #expect(stats.left == 171 && stats.right == 300)
        #expect(stats.fingers.count == 10)
        #expect(stats.fingers.first == HeatmapStats.FingerCount(hand: .left, finger: .pinky, presses: 21))
        #expect(stats.fingers[3] == HeatmapStats.FingerCount(hand: .left, finger: .index, presses: 50))
        #expect(stats.fingers[4] == HeatmapStats.FingerCount(hand: .left, finger: .thumb, presses: 100))
        #expect(stats.fingers[5] == HeatmapStats.FingerCount(hand: .right, finger: .thumb, presses: 300))
        #expect(stats.fingers.last?.finger == .pinky && stats.fingers.last?.hand == .right)
        #expect(stats.top.first == HeatmapStats.KeyCount(layer: 0, index: 51, presses: 300))
        #expect(stats.top.count == 5)
        #expect(stats.reached == [HeatmapStats.LayerReach(layer: 2, times: 7)])
    }

    /// Sums stop at `Int.max` rather than trap, so counts from a damaged file can't crash the lens or the inspector.
    @Test func sumsDontOverflow() {
        var hour = HeatmapHour(start: noon, presses: [main: [13: .max]], layerEntries: [main: .max])
        hour.add(HeatmapHour(start: noon, presses: [main: [13: 1]], layerEntries: [main: 1]))
        #expect(hour.presses[main]?[13] == .max && hour.layerEntries[main] == .max)
        let heat = KeyHeatmap([hour, HeatmapHour(start: noon.addingTimeInterval(3600), presses: [main: [13: 5, 51: .max]])])
        #expect(heat.count(layer: main, index: 13) == .max && heat.total() == .max && heat.total(layer: main) == .max)
        let stats = HeatmapStats(heat, layout: layout)
        #expect(stats.total == .max && stats.left == .max && stats.right == .max)
    }

    @Test func layersSinceDeletedAreLeftOut() {
        let heat = KeyHeatmap([HeatmapHour(start: noon, presses: [main: [13: 4], "deleted": [13: 99]], layerEntries: ["deleted": 2])])
        let stats = HeatmapStats(heat, layout: layout)
        #expect(stats.total == 4 && stats.left == 4 && stats.top.count == 1 && stats.reached.isEmpty)
    }

    /// The share bar and the reached list with many layers, on a twelve-layer layout built in code.
    @Test func twelveLayers() {
        var twelve = layout
        twelve.layers = (0..<12).map { Layer.transparent(title: "Layer \($0)") }
        let hours = twelve.layers.enumerated().map { n, item in
            HeatmapHour(start: noon, presses: [item.id: [n: n + 1]], layerEntries: n == 0 ? [:] : [item.id: n])
        }
        let stats = HeatmapStats(KeyHeatmap(hours), layout: twelve)
        #expect(stats.layers.count == 12 && stats.total == 78)
        #expect(stats.layers[11].presses == 12 && abs(stats.layers[11].share - 12.0 / 78) < 1e-12)
        #expect(stats.reached.map(\.layer) == Array(1..<12))
        #expect(stats.top.count == 8 && stats.top.first?.layer == 11)
    }

    // MARK: Fingers

    @Test func everyKeyHasAHandAndAFinger() {
        let keys = BoardDefinition.voyager.keys
        #expect(keys.filter { $0.hand == .left }.count == 26 && keys.filter { $0.hand == .right }.count == 26)
        #expect(keys.filter { $0.finger == .thumb }.map(\.index) == [24, 25, 50, 51])
        func finger(_ index: Int) -> BoardDefinition.Finger? { keys.first { $0.index == index }?.finger }
        // The home row, A S D F G and H J K L ; '.
        #expect([13, 14, 15, 16, 17].map(finger) == [.pinky, .ring, .middle, .index, .index])
        #expect([38, 39, 40, 41, 42, 43].map(finger) == [.index, .index, .middle, .ring, .pinky, .pinky])
        #expect(finger(12) == .pinky && finger(0) == .pinky)
        for finger in BoardDefinition.Finger.allCases where finger != .thumb {
            let left = keys.filter { $0.hand == .left && $0.finger == finger }.count
            #expect(left == keys.filter { $0.hand == .right && $0.finger == finger }.count, "\(finger) mirrors")
        }
    }

    // MARK: Export

    @Test func csvEscapesFormulasAndQuotes() {
        #expect(HeatmapExport.cell("=") == "\"'=\"")
        #expect(HeatmapExport.cell("=HYPERLINK(\"x\")") == "\"'=HYPERLINK(\"\"x\"\")\"")
        for lead in ["+1", "-", "@SUM(A1)", "\tx", "\rx", "\r\nx"] {
            #expect(HeatmapExport.cell(lead).hasPrefix("\"'"), "\(lead.debugDescription)")
        }
        #expect(HeatmapExport.cell("Sym+Num") == "\"Sym+Num\"")
        #expect(HeatmapExport.cell("a,b\nc") == "\"a,b\nc\"")
        #expect(HeatmapExport.cell("") == "\"\"")
    }

    @Test func csvRowsOnTheUsersLayout() {
        var renamed = layout
        renamed.layers[1].title = "=cmd|' /C calc'!A0"
        let csv = HeatmapExport.csv(sample(), layout: renamed)
        let lines = csv.components(separatedBy: "\r\n")
        #expect(lines.first == "layer,layer_name,key,legend,hand,finger,presses")
        #expect(lines.contains("0,\"Main\",0,\"'=\",\"left\",\"pinky\",1"), "the = legend can't run as a formula")
        #expect(lines.contains("0,\"Main\",51,\"␣\",\"right\",\"thumb\",300"))
        #expect(lines.contains("1,\"'=cmd|' /C calc'!A0\",16,\"(\",\"left\",\"index\",50"))
        #expect(lines.contains("layer,layer_name,times_reached"))
        #expect(lines.contains("2,\"Brd+Sys\",7"))
        #expect(lines.count(where: { $0.hasPrefix("0,") }) == 4 + 1, "four keys with presses, and Main's entries")
    }

    @Test func jsonCarriesTheRangeAndEveryCountedKey() throws {
        let data = try HeatmapExport.json(sample(), layout: layout, from: noon, to: noon.addingTimeInterval(7200))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["layout"] as? String == layout.title)
        #expect(object["from"] as? String == "2026-10-15T12:00:00Z")
        let keys = try #require(object["keys"] as? [[String: Any]])
        #expect(keys.count == 5)
        #expect(keys.contains { $0["key"] as? Int == 0 && $0["legend"] as? String == "=" && $0["presses"] as? Int == 1 })
        let layers = try #require(object["layers"] as? [[String: Any]])
        #expect(layers.map { $0["timesReached"] as? Int } == [0, 0, 7])
    }

    // MARK: Heat ramp

    @Test func rampEndsOnItsStopsAndStaysInOrder() throws {
        let stops = try ["#EAF1FB", "#B9D0F0", "#7FA8E3", "#3F74C8", "#123E8C"].map { try #require(HexColor(hex: $0)) }
        let ramp = HeatRamp(stops)
        #expect(ramp.color(at: 0).hex == "#EAF1FB")
        #expect(ramp.color(at: 0.5).hex == "#7FA8E3")
        #expect(ramp.color(at: 1).hex == "#123E8C")
        #expect(
            ramp.color(at: -1) == ramp.color(at: 0) && ramp.color(at: 2) == ramp.color(at: 1) && ramp.color(at: .nan) == ramp.color(at: 0))
        let luminances = stride(from: 0.0, through: 1, by: 0.05).map { ramp.color(at: $0).luminance }
        #expect(zip(luminances, luminances.dropFirst()).allSatisfy { $0 > $1 }, "light to dark, evenly")
    }
}
