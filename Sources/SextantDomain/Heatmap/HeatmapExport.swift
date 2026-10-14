import Foundation

/// The Heatmap's Export CSV… and Export JSON… (spec §8.5): one row per key with presses on each of the layout's layers,
/// then how often each layer was reached. Counts only, as stored (ADR 0053).
public enum HeatmapExport {
    /// One key's row.
    struct Row: Encodable {
        var layer: Int
        var layerName: String
        var key: Int
        var legend: String
        var hand: String
        var finger: String
        var presses: Int
    }

    /// `layer,layer_name,key,legend,hand,finger,presses`, then a blank line and `layer,layer_name,times_reached`. Text cells
    /// are quoted, and those a spreadsheet would run as a formula (the "=" legend, a layer named "+1") start with an
    /// apostrophe, which spreadsheets show as text.
    public static func csv(_ heatmap: KeyHeatmap, layout: KeyboardLayout, board: BoardDefinition = .voyager) -> String {
        var lines = ["layer,layer_name,key,legend,hand,finger,presses"]
        for row in rows(heatmap, layout: layout, board: board) {
            let cells = [
                "\(row.layer)", cell(row.layerName), "\(row.key)", cell(row.legend), cell(row.hand), cell(row.finger), "\(row.presses)",
            ]
            lines.append(cells.joined(separator: ","))
        }
        lines += ["", "layer,layer_name,times_reached"]
        for (layer, item) in layout.layers.enumerated() {
            lines.append("\(layer),\(cell(item.title)),\(heatmap.layerEntries[item.id] ?? 0)")
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// The same data as JSON, with the range it covers (`from` is nil for all of it).
    public static func json(
        _ heatmap: KeyHeatmap, layout: KeyboardLayout, from: Date?, to: Date, board: BoardDefinition = .voyager
    ) throws -> Data {
        struct Reach: Encodable {
            var layer: Int
            var layerName: String
            var timesReached: Int
        }
        struct File: Encodable {
            var layout: String
            var from: Date?
            var to: Date
            var keys: [Row]
            var layers: [Reach]
        }
        let reach = layout.layers.enumerated().map {
            Reach(layer: $0.offset, layerName: $0.element.title, timesReached: heatmap.layerEntries[$0.element.id] ?? 0)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(
            File(layout: layout.title, from: from, to: to, keys: rows(heatmap, layout: layout, board: board), layers: reach))
    }

    /// A text cell: quoted, its quotes doubled, and an apostrophe before a leading `=`, `+`, `-`, `@`, tab or carriage
    /// return, so a spreadsheet never runs it (OWASP's CSV injection advice).
    static func cell(_ text: String) -> String {
        // By scalar: "\r\n" is one Character, which isn't "\r".
        let guarded = text.unicodeScalars.first.map { "=+-@\t\r".unicodeScalars.contains($0) } == true ? "'" + text : text
        return "\"" + guarded.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Keys with presses, by layer then key.
    static func rows(_ heatmap: KeyHeatmap, layout: KeyboardLayout, board: BoardDefinition) -> [Row] {
        layout.layers.enumerated().flatMap { layer, item in
            (heatmap.presses[item.id] ?? [:]).filter { $0.value > 0 }.sorted { $0.key < $1.key }.map { index, count in
                let info = board.keys.first { $0.index == index }
                let legend = Legends.legend(layout: layout, layer: layer, index: index).legend.primary?.text ?? ""
                return Row(
                    layer: layer, layerName: item.title, key: index, legend: legend, hand: info?.hand.rawValue ?? "",
                    finger: info?.finger.rawValue ?? "", presses: count)
            }
        }
    }
}
