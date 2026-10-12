import Foundation

/// Picker categories (16), in display order. Macros holds the layout's own macros, not catalog entries.
public enum KeycodeCategory: String, CaseIterable, Hashable, Sendable, Identifiable {
    case letters, digits, modifiers, punctuation, navigation, editing, functionKeys, media, mouse, lighting, layers, system, international,
        numpad, navigator, macros

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .letters: "Letters"
        case .digits: "Digits"
        case .modifiers: "Modifiers"
        case .punctuation: "Punctuation"
        case .navigation: "Navigation"
        case .editing: "Editing"
        case .functionKeys: "Function Keys"
        case .media: "Media"
        case .mouse: "Mouse"
        case .lighting: "RGB & LEDs"
        case .layers: "Layers"
        case .system: "System & Firmware"
        case .international: "International"
        case .numpad: "Numpad"
        case .navigator: "Navigator"
        case .macros: "Macros"
        }
    }

    /// Neutral SF Symbol for a category list.
    public var symbolName: String {
        switch self {
        case .letters: "textformat.abc"
        case .digits: "textformat.123"
        case .modifiers: "command"
        case .punctuation: "ellipsis.curlybraces"
        case .navigation: "arrow.up.and.down.and.arrow.left.and.right"
        case .editing: "return"
        case .functionKeys: "fn"
        case .media: "playpause"
        case .mouse: "computermouse"
        case .lighting: "lightbulb"
        case .layers: "square.3.layers.3d"
        case .system: "gearshape"
        case .international: "globe"
        case .numpad: "number"
        case .navigator: "circle.circle"
        case .macros: "list.bullet.rectangle"
        }
    }
}

/// Which side a modifier sits on, for L/R legend subscripts.
public enum ModifierSide: String, Hashable, Sendable { case left, right }

/// One picker entry. Labels and names are Sextant's own wording (not copied from Oryx).
public struct KeycodeEntry: Identifiable, Hashable, Sendable {
    /// Canonical code as Oryx stores it (e.g. `KC_LEFT_SHIFT`, `KC_PGDN`, `QK_BOOT`, `MO`).
    public var code: String
    /// Other QMK spellings that mean the same key (`KC_LSFT`, `KC_LSHIFT`, …).
    public var aliases: [String]
    /// Short keycap text: a character or Mac glyph where one exists ("A", "⌘", "⏎", "Vol+").
    public var label: String
    /// Full readable name ("Left Command", "Volume Up").
    public var name: String
    /// SF Symbol name when a good one exists.
    public var symbol: String?
    /// Extra search words.
    public var keywords: [String]
    public var category: KeycodeCategory
    /// US-layout shifted character for digits and punctuation ("!" for 1).
    public var shiftedLabel: String?
    /// Left/right for side-specific modifiers.
    public var side: ModifierSide?
    /// True for layer functions that need a layer argument (MO, TG, TO, TT, OSL, LM, DF).
    public var needsLayer: Bool
    /// True for functions that need a modifier argument (OSM, LM).
    public var needsModifiers: Bool
    /// True when the action needs a colour argument (`RGB`).
    public var needsColor: Bool

    public var id: String { code }

    public init(
        code: String, aliases: [String] = [], label: String, name: String, symbol: String? = nil, keywords: [String] = [],
        category: KeycodeCategory, shiftedLabel: String? = nil, side: ModifierSide? = nil,
        needsLayer: Bool = false, needsModifiers: Bool = false, needsColor: Bool = false
    ) {
        self.code = code
        self.aliases = aliases
        self.label = label
        self.name = name
        self.symbol = symbol
        self.keywords = keywords
        self.category = category
        self.shiftedLabel = shiftedLabel
        self.side = side
        self.needsLayer = needsLayer
        self.needsModifiers = needsModifiers
        self.needsColor = needsColor
    }
}

/// The keycode catalog for pickers, legends and search.
public enum KeycodeCatalog {
    /// Every entry, grouped by category in display order.
    public static let entries: [KeycodeEntry] = KeycodeTable.build()

    private static let byCode: [String: KeycodeEntry] = {
        var map: [String: KeycodeEntry] = [:]
        for e in entries {
            map[e.code] = e
            for a in e.aliases where map[a] == nil { map[a] = e }
        }
        return map
    }()

    /// Looks up a code or any alias.
    public static func entry(for code: String) -> KeycodeEntry? { byCode[code] }

    /// Canonical spelling for a code (`KC_LSFT` → `KC_LEFT_SHIFT`); unknown codes are returned unchanged.
    public static func canonicalCode(_ code: String) -> String { byCode[code]?.code ?? code }

    /// Entries in one category.
    public static func entries(in category: KeycodeCategory) -> [KeycodeEntry] { entries.filter { $0.category == category } }

    /// Layer functions that take a layer argument.
    public static let layerFunctions: Set<String> = ["MO", "TG", "TO", "TT", "OSL", "LM", "DF"]

    /// Canonical modifier keycodes (plain modifiers, Hyper/Meh, Space Cadet).
    public static let modifierCodes: Set<String> = [
        "KC_LEFT_CTRL", "KC_LEFT_SHIFT", "KC_LEFT_ALT", "KC_LEFT_GUI",
        "KC_RIGHT_CTRL", "KC_RIGHT_SHIFT", "KC_RIGHT_ALT", "KC_RIGHT_GUI",
        "ALL_T", "MEH_T", "SC_LSPO", "SC_RSPC", "SC_LCPO", "SC_RCPC", "SC_LAPO", "SC_RAPC", "SC_SENT",
    ]

    /// Modifier bit for a plain modifier keycode (`KC_LEFT_GUI` → `.leftCommand`).
    public static func modifier(forCode code: String) -> Modifiers? {
        switch canonicalCode(code) {
        case "KC_LEFT_CTRL": .leftControl
        case "KC_LEFT_SHIFT": .leftShift
        case "KC_LEFT_ALT": .leftOption
        case "KC_LEFT_GUI": .leftCommand
        case "KC_RIGHT_CTRL": .rightControl
        case "KC_RIGHT_SHIFT": .rightShift
        case "KC_RIGHT_ALT": .rightOption
        case "KC_RIGHT_GUI": .rightCommand
        case "ALL_T": .hyper
        case "MEH_T": .meh
        default: nil
        }
    }

    // MARK: Search

    /// A ranked search result.
    public struct Match: Hashable, Sendable {
        public var entry: KeycodeEntry
        public var score: Int
    }

    /// Fuzzy search over labels, names, codes, aliases and keywords.
    ///
    /// Each whitespace-separated term must match some field. Per field, scores rank:
    /// exact (100) > prefix (80) > word prefix (70) > substring (50) > in-order subsequence (≤ 30).
    /// Labels and glyphs match exactly too, so "⌘", "⏎" or "[" work. Results are sorted by score,
    /// then category order, then catalog order. An empty query returns everything (optionally filtered).
    public static func search(_ query: String, category: KeycodeCategory? = nil, limit: Int? = nil) -> [KeycodeEntry] {
        rankedSearch(query, category: category, limit: limit).map(\.entry)
    }

    /// Like ``search(_:category:limit:)`` but with scores.
    public static func rankedSearch(_ query: String, category: KeycodeCategory? = nil, limit: Int? = nil) -> [Match] {
        let pool = category.map { entries(in: $0) } ?? entries
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            let all = pool.map { Match(entry: $0, score: 0) }
            return limit.map { Array(all.prefix($0)) } ?? all
        }
        // Single-character queries match labels literally (so "[" or "1" don't explode into fuzzy hits).
        let terms: [String] = q.count == 1 ? [q] : q.split(whereSeparator: \.isWhitespace).map(String.init)
        var results: [(Match, Int)] = []
        for (order, e) in pool.enumerated() {
            var total = 0
            var ok = true
            for t in terms {
                let s = score(term: t, entry: e)
                if s == 0 { ok = false; break }
                total += s
            }
            if ok { results.append((Match(entry: e, score: total), order)) }
        }
        let catOrder = Dictionary(uniqueKeysWithValues: KeycodeCategory.allCases.enumerated().map { ($1, $0) })
        results.sort { a, b in
            if a.0.score != b.0.score { return a.0.score > b.0.score }
            let ca = catOrder[a.0.entry.category, default: 0], cb = catOrder[b.0.entry.category, default: 0]
            if ca != cb { return ca < cb }
            return a.1 < b.1
        }
        let out = results.map(\.0)
        return limit.map { Array(out.prefix($0)) } ?? out
    }

    static func score(term: String, entry e: KeycodeEntry) -> Int {
        let t = fold(term)
        // Literal label hit wins (glyphs, punctuation, single letters).
        if e.label == term || fold(e.label) == t { return 110 }
        if let s = e.shiftedLabel, s == term { return 95 }
        if term.count == 1 { return 0 }
        var best = 0
        let codeShort = fold(e.code.replacingOccurrences(of: "KC_", with: ""))
        let fields: [(String, Int)] =
            [(fold(e.name), 0), (fold(e.label), 0), (fold(e.code), 0), (codeShort, 0)]
            + e.aliases.map { (fold($0), 5) } + e.keywords.map { (fold($0), 3) }
        for (f, penalty) in fields {
            var s = 0
            if f == t {
                s = 100
            } else if f.hasPrefix(t) {
                s = 80
            } else if f.split(whereSeparator: { $0 == " " || $0 == "_" || $0 == "-" || $0 == "/" }).contains(where: { $0.hasPrefix(t) }) {
                s = 70
            } else if f.contains(t) {
                s = 50
            } else if let first = t.first, startsWord(first, in: f), let gaps = subsequenceGaps(t, in: f) {
                s = max(5, 30 - gaps)
            }
            best = max(best, s - (s > 0 ? penalty : 0))
        }
        return best
    }

    static func fold(_ s: String) -> String { s.lowercased().folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil) }

    /// True if some word of `hay` starts with `ch` (keeps fuzzy matches anchored to a word start).
    static func startsWord(_ ch: Character, in hay: String) -> Bool {
        var atStart = true
        for h in hay {
            if atStart && h == ch { return true }
            atStart = h == " " || h == "_" || h == "-" || h == "/" || h == "("
        }
        return false
    }

    /// Number of skipped characters if `needle` is an in-order subsequence of `hay`.
    static func subsequenceGaps(_ needle: String, in hay: String) -> Int? {
        guard needle.count >= 2 else { return nil }
        var gaps = 0
        var it = hay.makeIterator()
        for ch in needle {
            var found = false
            while let h = it.next() {
                if h == ch { found = true; break }
                gaps += 1
            }
            if !found { return nil }
        }
        return gaps
    }
}
