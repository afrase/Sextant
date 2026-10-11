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

    /// True if this setting applies to the ZSA Voyager.
    public var appliesToVoyager: Bool { boards?.contains("voyager") ?? true }

    public static func == (a: Self, b: Self) -> Bool { a.id == b.id && a.defaultValue == b.defaultValue && a.title == b.title }
    public func hash(into h: inout Hasher) { h.combine(id) }

    /// Formats a value with its unit, e.g. "200 ms".
    public func format(_ value: SettingValue?) -> String {
        guard let value else { return "Off" }
        if case let .number(d) = value {
            if let m = marks[d] { return m }
            let n = Int(exactly: d).map(String.init) ?? String(format: "%.1f", d)
            switch unit {
            case "milliseconds", "ms": return "\(n) ms"
            case "seconds": return "\(n) s"
            case "minutes": return "\(n) min"
            case "degrees": return "\(n)°"
            default: return n
            }
        }
        return value.description
    }
}

/// A group of settings (14 sections).
public struct SettingsSection: Identifiable, Hashable, Sendable {
    /// Oryx slug, e.g. `tapping-dual`.
    public var id: String
    public var title: String
    public var summary: String
    /// Oryx hides Audio on the Voyager; Navigator is shown only with a Navigator attached.
    public var isVisibleOnVoyager: Bool
    public var settings: [Setting]
}

/// The bundled, trimmed firmware settings catalog: 14 sections, 100 settings.
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

    /// Case- and diacritic-insensitive search over titles, summaries and ids.
    public func search(_ query: String) -> [Setting] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return allSettings }
        let terms = q.lowercased().folding(options: .diacriticInsensitive, locale: nil).split(separator: " ")
        return allSettings.filter { s in
            let hay = "\(s.title) \(s.summary) \(s.id)".lowercased().folding(options: .diacriticInsensitive, locale: nil)
            return terms.allSatisfy { hay.contains($0) }
        }
    }

    /// Settings whose value in `overrides` differs from the default (what a "Modified" filter shows).
    public func modified(in overrides: [String: SettingValue]) -> [Setting] {
        allSettings.filter { s in overrides[s.id].map { $0 != s.defaultValue } ?? false }
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
                requiresPerKeyLighting: requiresPerKeyLighting ?? false)
        }
    }
    var sections: [Section]
}
