import Foundation
import SextantApplication
import SextantDomain
import Testing
import UniformTypeIdentifiers

@testable import SextantUI

/// The Heatmap lens's window side (spec §8.5, ADR 0053): the lens itself, the caps' heat and counts and what VoiceOver
/// says of them, the exports, and the menu bar's typing line. Counts are fixed values on the user's layout.
@MainActor
struct HeatmapLensTests {
    func model(layer: Int = 0) async throws -> LayoutWindowModel {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        let main = session.layout.layers[0].id
        let hour = HeatmapHour(start: HeatmapHour.start(of: Date()), presses: [main: [51: 300, 24: 100, 13: 22_044]])
        model.heatmap.show([hour], of: session.id, range: .week, status: .recording(session.id))
        session.select(layer: layer)
        model.lens = .heatmap
        return model
    }

    @Test func heatmapIsTheThirdLens() {
        // View ▸ Lens and the palette number the lenses ⌃⌘1–3 in this order.
        #expect(Lens.allCases == [.keys, .lighting, .heatmap])
        #expect(Lens.heatmap.title == "Heatmap")
    }

    @Test func capsShowHeatAndTheirCount() async throws {
        let model = try await model()
        let session = try #require(model.session)
        let hottest = model.capDecoration(layer: 0, index: 13)
        #expect(hottest.fill == Tokens.heat(1) && hottest.count?.text == "22k")
        #expect(hottest.count?.accessibilityText == "22,044 presses")
        let space = model.capDecoration(layer: 0, index: 51)
        #expect(space.count?.text == "300" && space.fill == Tokens.heat(log1p(300) / log1p(22_044)))
        let unused = model.capDecoration(layer: 0, index: 0)
        #expect(unused.fill == Tokens.heat(0) && unused.count?.text == "0" && unused.count?.accessibilityText == "No presses")
        let resolved = Legends.legend(layout: session.layout, layer: 0, index: 13)
        let value = KeyText.value(resolved, layout: session.layout, layer: 0, index: 13, geometry: .voyager, decoration: hottest)
        #expect(value.hasSuffix(" 22,044 presses."))
    }

    @Test func plainCapsElsewhere() async throws {
        let model = try await model()
        #expect(model.capDecoration(layer: 1, index: 13) == CapDecoration(), "a layer with no presses in the range")
        model.lens = .keys
        #expect(model.capDecoration(layer: 0, index: 13) == CapDecoration())
        model.lens = .heatmap
        model.destination = .combos
        #expect(model.capDecoration(layer: 0, index: 13).fill == nil, "Combos draws its own marks")
    }

    @Test func compactCounts() {
        #expect(
            [0, 312, 999, 1000, 1240, 9_999, 22_044, 999_999, 1_400_000].map(HeatCount.compact) == [
                "0", "312", "999", "1k", "1.2k", "10k", "22k", "999k", "1.4M",
            ])
        #expect(HeatCount.spoken(1) == "1 press")
    }

    @Test func exportsGoToTheSavePanel() async throws {
        let model = try await model()
        model.exportHeatmap(json: false)
        let csv = try #require(model.pendingExport?.file)
        #expect(csv.contentType == .commaSeparatedText && csv.filename == "My MacOS Layout Heatmap")
        #expect(String(bytes: csv.data, encoding: .utf8)?.hasPrefix("layer,layer_name,key,legend,hand,finger,presses\r\n") == true)
        model.exportHeatmap(json: true)
        #expect(model.pendingExport?.file?.contentType == .commaSeparatedText, "one panel at a time")
        model.pendingExport = nil
        model.exportHeatmap(json: true)
        let json = try #require(model.pendingExport?.file)
        #expect(json.contentType == .json)
        let object = try JSONSerialization.jsonObject(with: json.data) as? [String: Any]
        #expect((object?["keys"] as? [Any])?.count == 3)
    }

    @Test func typingLine() {
        #expect(TypingStats(today: 12_408, wordsPerMinute: 64).text == "Today: 12,408 presses · 64 wpm")
        #expect(TypingStats(today: nil, wordsPerMinute: 0).text == "Today: No presses")
        #expect(TypingStats(today: 3, wordsPerMinute: 0, pause: "Paused: Live View is off").text == "Heatmap · Paused: Live View is off")
    }
}
