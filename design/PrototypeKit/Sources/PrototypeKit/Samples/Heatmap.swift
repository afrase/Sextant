import Foundation

/// Key-press counts per layer and key, plus layer usage, over a period.
public struct KeyHeatmap: Hashable, Sendable {
    public var period: DateInterval
    /// `counts[layer][keyIndex]` = presses while that layer was the top active layer.
    public var counts: [[Int]]
    /// Number of times each layer was activated (index 0 = time spent on base, counted as sessions).
    public var layerActivations: [Int]
    /// Share of keystrokes typed on each layer (sums to 1).
    public var layerShare: [Double]

    /// Presses for one key.
    public func count(layer: Int, index: Int) -> Int {
        guard counts.indices.contains(layer), counts[layer].indices.contains(index) else { return 0 }
        return counts[layer][index]
    }

    /// Total presses on a layer, or on every layer when `layer` is nil.
    public func total(layer: Int? = nil) -> Int {
        if let layer { return counts.indices.contains(layer) ? counts[layer].reduce(0, +) : 0 }
        return counts.joined().reduce(0, +)
    }

    /// Highest single-key count on a layer.
    public func maxCount(layer: Int) -> Int { counts.indices.contains(layer) ? (counts[layer].max() ?? 0) : 0 }

    /// 0...1 intensity relative to the busiest key on the layer. `logarithmic` spreads out the long tail.
    public func intensity(layer: Int, index: Int, logarithmic: Bool = true) -> Double {
        let m = Double(maxCount(layer: layer)), c = Double(count(layer: layer, index: index))
        guard m > 0, c > 0 else { return 0 }
        return logarithmic ? log1p(c) / log1p(m) : c / m
    }

    /// Busiest keys on a layer.
    public func top(_ n: Int, layer: Int) -> [(index: Int, count: Int)] {
        guard counts.indices.contains(layer) else { return [] }
        return counts[layer].enumerated().sorted { $0.element > $1.element }.prefix(n).map { (index: $0.offset, count: $0.element) }
    }

    /// CSV export: `layer,layer_name,key_index,legend,count`.
    public func csv(layout: KeyboardLayout) -> String {
        var rows = ["layer,layer_name,key_index,legend,count"]
        for (l, layerCounts) in counts.enumerated() {
            for (i, c) in layerCounts.enumerated() where c > 0 {
                let legend = Legends.legend(layout: layout, layer: l, index: i).legend.primary?.text ?? ""
                let name = layout.layers.indices.contains(l) ? layout.layers[l].title : "Layer \(l)"
                rows.append("\(l),\"\(name)\",\(i),\"\(legend.replacingOccurrences(of: "\"", with: "\"\""))\",\(c)")
            }
        }
        return rows.joined(separator: "\n")
    }

    /// A plausible week of English typing on the user's layout, ~140k keystrokes.
    /// Letter counts follow English letter frequency; the rest is modelled on a Mac developer's habits.
    public static func sample(layout: KeyboardLayout, keystrokes: Int = 140_000) -> KeyHeatmap {
        let n = layout.keyCount
        var counts = Array(repeating: Array(repeating: 0, count: n), count: max(3, layout.layers.count))
        // Per-mille shares of all keystrokes.
        let letters: [Character: Double] = [
            "E": 89, "T": 64, "A": 58, "O": 53, "I": 50, "N": 48, "S": 45, "H": 43, "R": 43, "D": 30, "L": 29,
            "C": 20, "U": 20, "M": 17, "W": 17, "F": 16, "G": 14, "Y": 14, "P": 14, "B": 11, "V": 7, "K": 6,
            "J": 1.1, "X": 1.1, "Q": 0.7, "Z": 0.5,
        ]
        var base: [String: Double] = [:]
        for (ch, v) in letters { base["KC_\(ch)"] = v }
        let other: [String: Double] = [
            "KC_SPACE": 150, "KC_BSPC": 52, "KC_ENTER": 16, "KC_LEFT_SHIFT": 17, "KC_QUOTE": 12, "KC_COMMA": 11, "KC_DOT": 10,
            "KC_TAB": 7, "KC_EQUAL": 5, "KC_SCLN": 3, "KC_MINUS": 3, "KC_SLASH": 4, "KC_BSLS": 0.4, "KC_LEFT_CTRL": 5,
            "KC_LEFT_GUI": 30, "KC_RIGHT_CTRL": 0.8,
            "KC_1": 2.2, "KC_2": 2.0, "KC_3": 1.6, "KC_4": 1.3, "KC_5": 1.2, "KC_6": 1.0, "KC_7": 0.9, "KC_8": 0.9, "KC_9": 1.0, "KC_0": 1.8,
        ]
        for (k, v) in other { base[k] = v }
        // Hold actions add presses on the same physical key.
        let holdExtra: [Int: Double] = [0: 6 /* Esc */, 19: 4 /* ⌥ */, 48: 2, 43: 8 /* right ⇧ */, 24: 0, 51: 0]
        var rng = SplitMix(seed: 0x5E7A47)
        func jitter() -> Double { 0.9 + rng.nextUnit() * 0.2 }
        let perMille = Double(keystrokes) / 1000
        for (i, key) in layout.layers[0].keys.enumerated() {
            var v = 0.0
            for (_, a) in key.actions { v += base[a.canonicalCode] ?? 0 }
            v += holdExtra[i] ?? 0
            counts[0][i] = Int((v * perMille * jitter()).rounded())
        }
        // Sym+Num (layer 1): brackets, digits and operators.
        let sym: [Int: Double] = [
            16: 9, 17: 9, 20: 4, 21: 4, 22: 6, 23: 6, 13: 1.5, 14: 2, 15: 2.5, 7: 2, 8: 1.5, 9: 1.2, 10: 1.6, 11: 0.8, 6: 2.4, 0: 2.2,
            32: 2.5, 33: 2.2, 34: 2.1, 38: 2.4, 39: 2.3, 40: 2.2, 44: 3.4, 45: 3.0, 46: 2.6, 51: 3.6, 47: 1.8, 48: 3.0, 41: 1.6,
            42: 1.2, 35: 1.5, 36: 1.4, 49: 0.8, 43: 1.0, 50: 0.6, 1: 0.6, 2: 0.4, 3: 0.4, 4: 0.3, 5: 0.5, 26: 0.3, 27: 0.3, 28: 0.2,
            29: 0.2, 30: 0.2, 31: 0.2, 37: 0.4,
        ]
        for (i, v) in sym where i < n { counts[1][i] = Int((v * perMille * jitter()).rounded()) }
        // Brd+Sys (layer 2): arrows dominate, then tab/history shortcuts and media.
        let nav: [Int: Double] = [
            38: 11, 39: 9, 40: 9, 41: 11, 32: 2.2, 35: 2.4, 33: 1.4, 34: 1.4, 44: 3.2, 47: 1.6, 45: 2.6, 46: 2.8,
            8: 0.9, 9: 1.1, 10: 0.4, 16: 0.9, 13: 0.3, 14: 0.4, 15: 0.1, 4: 0.2, 5: 0.3, 0: 0.05, 2: 0.05, 6: 0.3, 7: 0.2,
            21: 0.02, 22: 0.02, 23: 0.02, 31: 0.01, 1: 0.03, 3: 0.02,
        ]
        for (i, v) in nav where i < n { counts[2][i] = Int((v * perMille * jitter()).rounded()) }
        // The thumb keys that hold each layer are pressed once per activation.
        let activations = [0, 2_140, 1_630]
        counts[0][24] += activations[1]
        counts[0][51] += activations[2]
        let totals = counts.map { Double($0.reduce(0, +)) }
        let all = totals.reduce(0, +)
        let start = Date(timeIntervalSince1970: 1_791_072_000) // 2026-10-04 00:00 UTC
        return KeyHeatmap(period: DateInterval(start: start, duration: 7 * 86_400), counts: counts,
                          layerActivations: activations, layerShare: totals.map { all > 0 ? $0 / all : 0 })
    }
}

/// Small deterministic PRNG for mock data.
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func nextUnit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}
