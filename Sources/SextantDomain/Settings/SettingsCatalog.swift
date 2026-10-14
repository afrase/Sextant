import Foundation

/// A firmware setting value. Oryx stores booleans, numbers and layer/animation lists.
public enum SettingValue: Hashable, Sendable, Codable, CustomStringConvertible {
    case bool(Bool)
    case number(Double)
    case text(String)
    /// Layer indices (`aimLayers`, …).
    case integers([Int])
    /// Ids (`disabledAnimations`).
    case strings([String])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let d = try? c.decode(Double.self) {
            self = .number(d)
        } else if let s = try? c.decode(String.self) {
            self = .text(s)
        } else if let i = try? c.decode([Int].self) {
            self = .integers(i)
        } else if let s = try? c.decode([String].self) {
            self = .strings(s)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unsupported setting value"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case let .bool(b): try c.encode(b)
        case let .number(d): try c.encode(d)
        case let .text(s): try c.encode(s)
        case let .integers(i): try c.encode(i)
        case let .strings(s): try c.encode(s)
        }
    }

    // `[]` decodes as `.integers([])`, so an empty list must equal an empty list of either type.
    public static func == (a: Self, b: Self) -> Bool {
        switch (a, b) {
        case let (.bool(x), .bool(y)): x == y
        case let (.number(x), .number(y)): x == y
        case let (.text(x), .text(y)): x == y
        case let (.integers(x), .integers(y)): x == y
        case let (.strings(x), .strings(y)): x == y
        case let (.integers(x), .strings(y)), let (.strings(y), .integers(x)): x.isEmpty && y.isEmpty
        default: false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case let .bool(b): hasher.combine(b)
        case let .number(d): hasher.combine(d)
        case let .text(s): hasher.combine(s)
        case let .integers(i): if i.isEmpty { hasher.combine(0) } else { hasher.combine(i) }
        case let .strings(s): if s.isEmpty { hasher.combine(0) } else { hasher.combine(s) }
        }
    }

    public var boolValue: Bool? { if case let .bool(b) = self { b } else { nil } }
    public var doubleValue: Double? { if case let .number(d) = self { d } else { nil } }

    public var description: String {
        switch self {
        case let .bool(b): b ? "On" : "Off"
        case let .number(d): Int(exactly: d).map(String.init) ?? String(d)
        case let .text(s): s
        case let .integers(i): i.map(String.init).joined(separator: ", ")
        case let .strings(s): s.joined(separator: ", ")
        }
    }
}

/// One firmware setting from the bundled catalog (ids, types, defaults and ranges match Oryx; text is Sextant's).
public struct Setting: Identifiable, Hashable, Sendable {
    public enum Control: String, Hashable, Sendable {
        case toggle, slider
        /// Pick layers (Navigator aim/turbo/drag-scroll layers).
        case layerSelect = "layer-select"
        /// Pick animations to exclude (`disabledAnimations`).
        case animationSelect = "animation-select"
    }

    public struct Option: Identifiable, Hashable, Sendable {
        public var id: String
        public var title: String
    }

    /// Oryx config key, e.g. `tappingTerm`.
    public var id: String
    public var title: String
    public var summary: String
    public var control: Control
    /// Default; nil for toggleable sliders that are off by default (one-shot settings).
    public var defaultValue: SettingValue?
    public var range: ClosedRange<Double>?
    /// Unit as Oryx states it (`milliseconds`, `seconds`, `minutes`, `degrees`, `ms`), when known.
    public var unit: String?
    /// A slider that can also be switched off entirely.
    public var isToggleable: Bool
    /// Named slider positions (Navigator aim/turbo speed).
    public var marks: [Double: String]
    /// Restricts the setting to some boards; nil means every board. (`chordalHoldExcludeThumbs`, `enableNavigator`.)
    public var boards: [String]?
    /// Restricts a Navigator setting to device kinds (`trackball`, `trackpad`).
    public var navigatorKinds: [String]?
    /// Shown only when another setting has a value (`oneShotAutoMouseTimeout` needs `oneShotAutoMouse`).
    public var dependsOn: (id: String, value: SettingValue)?
    /// Options for ``Control/animationSelect``.
    public var options: [Option]
    /// Oryx hides these on boards without per-key RGB.
    public var requiresPerKeyLighting: Bool
    /// Other words people search for it by, in Sextant's own words ("chatter" finds debounce).
    public var synonyms: [String] = []

    /// True if this setting applies to the ZSA Voyager.
    public var appliesToVoyager: Bool { boards?.contains("voyager") ?? true }

    public static func == (a: Self, b: Self) -> Bool { a.id == b.id && a.defaultValue == b.defaultValue && a.title == b.title }
    public func hash(into h: inout Hasher) { h.combine(id) }

    /// Formats a value with its unit, e.g. "200 ms"; animations as how many are in ("46 of 48"), and an empty layer
    /// list as "None".
    public func format(_ value: SettingValue?) -> String {
        guard let value else { return "Off" }
        if case let .number(d) = value {
            if let m = marks[d] { return m }
            let n = Int(exactly: d).map(String.init) ?? String(format: "%.1f", d)
            return unitSymbol.isEmpty || unitSymbol == "°" ? n + unitSymbol : "\(n) \(unitSymbol)"
        }
        if control == .animationSelect {
            let excluded: Set<String> = if case let .strings(ids) = value { Set(ids) } else { [] }
            return String(localized: "\(options.count { !excluded.contains($0.id) }) of \(options.count)")
        }
        if control == .layerSelect, value == .integers([]) { return String(localized: "None") }
        return value.description
    }
}

/// A group of settings (14 sections).
public struct SettingsSection: Identifiable, Hashable, Sendable {
    /// Oryx slug, e.g. `tapping-dual`.
    public var id: String
    public var title: String
    public var summary: String
    /// Oryx hides Audio on the Voyager.
    public var isVisibleOnVoyager: Bool
    public var settings: [Setting]
}

/// The bundled, trimmed firmware settings catalog: 14 sections, 101 settings.
public struct SettingsCatalog: Sendable {
    public var sections: [SettingsSection]

    /// The Voyager catalog, embedded in the binary (ADR 0008). `SettingsCatalogTests` proves it decodes.
    public static let voyager: SettingsCatalog = {
        do { return try Self(data: Data(SettingsCatalogData.json.utf8)) } catch {
            fatalError("Embedded settings catalog failed to decode: \(error)")
        }
    }()

    public init(sections: [SettingsSection]) { self.sections = sections }

    /// Parses the catalog JSON format.
    public init(data: Data) throws {
        let raw = try JSONDecoder().decode(RawCatalog.self, from: data)
        sections = raw.sections.map { s in
            SettingsSection(
                id: s.id, title: s.title, summary: s.summary, isVisibleOnVoyager: s.visibleOnVoyager ?? true,
                settings: s.settings.map { $0.model })
        }
    }

    /// Every setting, in section order.
    public var allSettings: [Setting] { sections.flatMap(\.settings) }

    public func setting(id: String) -> Setting? { allSettings.first { $0.id == id } }

    public func section(containing id: String) -> SettingsSection? { sections.first { $0.settings.contains { $0.id == id } } }

    /// Case- and diacritic-insensitive search over titles, summaries, ids and synonyms: every word must match.
    public func search(_ query: String) -> [Setting] { allSettings.filter { Self.matches($0, query) } }

    /// Whether `setting` matches a ``search(_:)`` query; an empty query matches everything.
    public static func matches(_ setting: Setting, _ query: String) -> Bool {
        matches(([setting.title, setting.summary, setting.id] + setting.synonyms).joined(separator: " "), query)
    }

    /// Whether every word of `query` is in `text`, ignoring case and diacritics.
    public static func matches(_ text: String, _ query: String) -> Bool {
        let hay = fold(text)
        return fold(query).split(whereSeparator: \.isWhitespace).allSatisfy { hay.contains($0) }
    }

    private static func fold(_ s: String) -> String { s.lowercased().folding(options: .diacriticInsensitive, locale: nil) }

    // MARK: What Sextant offers (ADR 0040, 0041)

    /// Settings Sextant keeps but never offers: "Prefer tap in tap-and-hold dances" (the firmware is the same either
    /// way), the live connection (always on: Sextant's live view needs it) and steno (Sextant has no steno keycodes).
    static let hiddenIDs: Set<String> = ["dancesTapAction", "liveTraining", "stenography", "geminipr"]

    /// The International toggles Sextant has keycodes for, and the prefix of the codes each adds to the picker.
    public static let localeCodePrefixes: [String: String] = ["uk": "UK_", "usint": "US_"]

    /// Whether Sextant offers `setting` for the Voyager: on the Firmware Settings page, in the palette and in the
    /// changed counts. A setting it doesn't offer keeps an imported value, which its builds don't use.
    public func offers(_ setting: Setting) -> Bool {
        guard setting.appliesToVoyager, !Self.hiddenIDs.contains(setting.id), let section = section(containing: setting.id),
            section.isVisibleOnVoyager
        else { return false }
        return section.id != "international" || Self.localeCodePrefixes[setting.id] != nil
    }
}

private struct RawCatalog: Decodable {
    struct Section: Decodable {
        var id: String
        var title: String
        var summary: String
        var visibleOnVoyager: Bool?
        var settings: [RawSetting]
    }
    struct DependsOn: Decodable { var key: String; var value: SettingValue }
    struct RawOption: Decodable { var id: String; var title: String }
    struct RawSetting: Decodable {
        var id: String
        var title: String
        var summary: String
        var type: String
        var `default`: SettingValue?
        var min: Double?
        var max: Double?
        var unit: String?
        var toggleable: Bool?
        var marks: [String: String]?
        var boards: [String]?
        var navigatorKinds: [String]?
        var dependsOn: DependsOn?
        var options: [RawOption]?
        var requiresPerKeyLighting: Bool?
        var synonyms: [String]?

        var model: Setting {
            var defaultValue = self.default
            if case .integers(let a)? = defaultValue, a.isEmpty, type == "animation-select" { defaultValue = .strings([]) }
            return Setting(
                id: id, title: title, summary: summary, control: Setting.Control(rawValue: type) ?? .toggle,
                defaultValue: defaultValue, range: min.flatMap { lo in max.map { lo...$0 } }, unit: unit,
                isToggleable: toggleable ?? false,
                marks: Dictionary(uniqueKeysWithValues: (marks ?? [:]).compactMap { k, v in Double(k).map { ($0, v) } }),
                boards: boards, navigatorKinds: navigatorKinds,
                dependsOn: dependsOn.map { (id: $0.key, value: $0.value) },
                options: (options ?? []).map { Setting.Option(id: $0.id, title: $0.title) },
                requiresPerKeyLighting: requiresPerKeyLighting ?? false, synonyms: synonyms ?? [])
        }
    }
    var sections: [Section]
}
