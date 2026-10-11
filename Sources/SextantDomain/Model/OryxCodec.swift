import Foundation

/// Errors from decoding a layout.
public enum OryxDecodingError: Error, Equatable, Sendable, CustomStringConvertible {
    case missingRevision
    /// The layout is for a board Sextant doesn't know (Oryx geometry name).
    case unsupportedBoard(String)
    case badLayerKeyCount(layer: String, count: Int, expected: Int)

    public var description: String {
        switch self {
        case .missingRevision: "The JSON has no layout revision."
        case let .unsupportedBoard(name): "The layout is for \(name), which Sextant doesn't support yet."
        case let .badLayerKeyCount(layer, count, expected): "Layer \(layer) has \(count) keys instead of \(expected)."
        }
    }
}

// The document codec (ADR 0007): `KeyboardLayout` reads and writes Oryx's layout JSON shape
// (`{hashId, title, geometry, revision: {layers, config, combos, navigators, swatch, …}}`).
// One format serves Oryx import, `.sextant` storage and export. Nil fields are omitted on write.
// Oryx's leaked UI state and display-only fields (icon, emoji, about, tour) are ignored on read.

extension KeyboardLayout: Codable {
    /// Decodes Oryx's GraphQL response (`{"data":{"layout":…}}`) or a bare layout object.
    public init(oryxJSON data: Data) throws {
        let decoder = JSONDecoder()
        // A bare layout has no `data` key; errors inside a real envelope propagate as themselves.
        if let layout = try decoder.decode(Envelope.self, from: data).data?.layout {
            self = layout
        } else {
            self = try decoder.decode(KeyboardLayout.self, from: data)
        }
    }

    private struct Envelope: Decodable {
        struct Box: Decodable { var layout: KeyboardLayout }
        var data: Box?
    }

    private enum LayoutKeys: String, CodingKey { case hashId, title, geometry, revision }
    private enum RevisionKeys: String, CodingKey {
        case hashId, qmkVersion, md5, createdAt, title, config, layers, combos, navigators, swatch
    }
    private struct Swatch: Codable { var colors: [HexColor] }
    private struct Navigators: Codable { var left: NavigatorOptions?, right: NavigatorOptions? }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: LayoutKeys.self)
        guard c.contains(.revision) else { throw OryxDecodingError.missingRevision }
        let r = try c.nestedContainer(keyedBy: RevisionKeys.self, forKey: .revision)
        let geometry = try c.decodeIfPresent(String.self, forKey: .geometry) ?? "voyager"

        guard let board = BoardDefinition.named(geometry) else { throw OryxDecodingError.unsupportedBoard(geometry) }
        var layers = try r.decodeIfPresent([PositionedLayer].self, forKey: .layers) ?? []
        layers.sort { $0.position < $1.position }
        if let bad = layers.first(where: { $0.layer.keys.count != board.keyCount }) {
            throw OryxDecodingError.badLayerKeyCount(layer: bad.layer.title, count: bad.layer.keys.count, expected: board.keyCount)
        }

        let rawCombos = try r.decodeIfPresent([Combo].self, forKey: .combos) ?? []
        var navigator: NavigatorConfig?
        if let n = try r.decodeIfPresent(Navigators.self, forKey: .navigators) {
            // shortcut: one Navigator per layout (the Voyager takes one), left wins if Oryx ever sends both.
            navigator = n.left.flatMap { $0.config(side: .left) } ?? n.right.flatMap { $0.config(side: .right) }
        }

        var oryx: OryxRevisionInfo?
        if let layoutId = try c.decodeIfPresent(String.self, forKey: .hashId),
            let revisionId = try r.decodeIfPresent(String.self, forKey: .hashId)
        {
            oryx = OryxRevisionInfo(
                layoutId: layoutId, revisionId: revisionId,
                firmwareVersion: try r.decodeIfPresent(String.self, forKey: .qmkVersion),
                md5: try r.decodeIfPresent(String.self, forKey: .md5),
                createdAt: try r.decodeIfPresent(String.self, forKey: .createdAt),
                message: try r.decodeIfPresent(String.self, forKey: .title))
        }

        self.init(
            title: try c.decodeIfPresent(String.self, forKey: .title) ?? "Untitled Layout",
            geometry: geometry,
            layers: layers.map(\.layer),
            combos: rawCombos.enumerated().map { i, combo in
                var combo = combo
                combo.id = "combo-\(i)"
                return combo
            },
            settings: try r.decodeIfPresent(LenientDictionary.self, forKey: .config)?.values ?? [:],
            navigator: navigator,
            swatch: try r.decodeIfPresent(Swatch.self, forKey: .swatch)?.colors ?? [],
            oryx: oryx)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: LayoutKeys.self)
        try c.encodeIfPresent(oryx?.layoutId, forKey: .hashId)
        try c.encode(title, forKey: .title)
        try c.encode(geometry, forKey: .geometry)
        var r = c.nestedContainer(keyedBy: RevisionKeys.self, forKey: .revision)
        try r.encodeIfPresent(oryx?.revisionId, forKey: .hashId)
        try r.encodeIfPresent(oryx?.firmwareVersion, forKey: .qmkVersion)
        try r.encodeIfPresent(oryx?.md5, forKey: .md5)
        try r.encodeIfPresent(oryx?.createdAt, forKey: .createdAt)
        try r.encodeIfPresent(oryx?.message, forKey: .title)
        try r.encode(settings, forKey: .config)
        try r.encode(layers.enumerated().map { PositionedLayer(position: $0, layer: $1) }, forKey: .layers)
        if !combos.isEmpty { try r.encode(combos, forKey: .combos) }
        if let navigator {
            let options = NavigatorOptions(navigator)
            try r.encode(navigator.side == .left ? Navigators(left: options) : Navigators(right: options), forKey: .navigators)
        }
        if !swatch.isEmpty { try r.encode(Swatch(colors: swatch), forKey: .swatch) }
    }
}

/// A layer with Oryx's `position`, used only while coding.
private struct PositionedLayer: Codable {
    var position: Int
    var layer: Layer

    private enum Keys: String, CodingKey { case hashId, title, color, position, keys }

    init(position: Int, layer: Layer) {
        self.position = position
        self.layer = layer
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        position = try c.decodeIfPresent(Int.self, forKey: .position) ?? 0
        let keys = try c.decodeIfPresent([Key?].self, forKey: .keys) ?? []
        layer = Layer(
            id: try c.decodeIfPresent(String.self, forKey: .hashId) ?? UUID().uuidString,
            title: try c.decodeIfPresent(String.self, forKey: .title) ?? "Layer",
            color: try c.decodeIfPresent(LenientColor.self, forKey: .color)?.color,
            keys: keys.map { $0 ?? .transparent })
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(layer.id, forKey: .hashId)
        try c.encode(layer.title, forKey: .title)
        try c.encodeIfPresent(layer.color, forKey: .color)
        try c.encode(position, forKey: .position)
        try c.encode(layer.keys, forKey: .keys)
    }
}

extension Key: Codable {
    private enum Keys: String, CodingKey {
        case tap, hold, doubleTap, tapHold, customLabel, glowColor, lockGlowColor, tappingTerm
    }
    private enum CodeKey: String, CodingKey { case code }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        // A slot that is null, or an object without a code, is empty.
        func slot(_ key: Keys) throws -> KeyAction? {
            guard let step = try? c.nestedContainer(keyedBy: CodeKey.self, forKey: key),
                try step.decodeIfPresent(String.self, forKey: .code) != nil
            else { return nil }
            return try c.decode(KeyAction.self, forKey: key)
        }
        let label = try c.decodeIfPresent(String.self, forKey: .customLabel)
        self.init(
            tap: try slot(.tap),
            hold: try slot(.hold),
            doubleTap: try slot(.doubleTap),
            tapHold: try slot(.tapHold),
            customLabel: label?.isEmpty == true ? nil : label,
            glowColor: try c.decodeIfPresent(LenientColor.self, forKey: .glowColor)?.color,
            lockGlowColor: try c.decodeIfPresent(LenientColor.self, forKey: .lockGlowColor)?.color,
            tappingTerm: try c.decodeIfPresent(Int.self, forKey: .tappingTerm))
        // Oryx generates KC_TRANSPARENT for a key with no actions; store it that way so there is one representation.
        if filledSlots.isEmpty { tap = .transparent }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encodeIfPresent(tap, forKey: .tap)
        try c.encodeIfPresent(hold, forKey: .hold)
        try c.encodeIfPresent(doubleTap, forKey: .doubleTap)
        try c.encodeIfPresent(tapHold, forKey: .tapHold)
        try c.encodeIfPresent(customLabel, forKey: .customLabel)
        try c.encodeIfPresent(glowColor, forKey: .glowColor)
        try c.encodeIfPresent(lockGlowColor, forKey: .lockGlowColor)
        try c.encodeIfPresent(tappingTerm, forKey: .tappingTerm)
    }
}

extension KeyAction: Codable {
    private enum Keys: String, CodingKey { case code, layer, modifier, modifiers, macro, color, description }

    /// Decodes an Oryx `KeyStep`. Its `modifier` (`MOD_LSFT`, used by OSM and LM) folds into ``modifiers``.
    /// A step with no `code` is invalid; callers decode slots as optionals and Oryx writes `null` for empty slots.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        var mods = try c.decodeIfPresent(Modifiers.self, forKey: .modifiers) ?? []
        if let mask = try c.decodeIfPresent(String.self, forKey: .modifier), let m = Modifiers(qmkMask: mask) {
            mods.formUnion(m)
        }
        self.init(
            code: try c.decode(String.self, forKey: .code),
            layer: try c.decodeIfPresent(Int.self, forKey: .layer),
            modifiers: mods,
            macro: try c.decodeIfPresent(Macro.self, forKey: .macro),
            color: try c.decodeIfPresent(LenientColor.self, forKey: .color)?.color,
            description: try c.decodeIfPresent(String.self, forKey: .description))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(code, forKey: .code)
        try c.encodeIfPresent(layer, forKey: .layer)
        if !modifiers.isEmpty { try c.encode(modifiers, forKey: .modifiers) }
        try c.encodeIfPresent(macro, forKey: .macro)
        try c.encodeIfPresent(color, forKey: .color)
        try c.encodeIfPresent(description, forKey: .description)
    }
}

extension Modifiers: Codable {
    private static let names: [(Modifiers, String)] = [
        (.leftControl, "leftCtrl"), (.leftShift, "leftShift"), (.leftOption, "leftAlt"), (.leftCommand, "leftGui"),
        (.rightControl, "rightCtrl"), (.rightShift, "rightShift"), (.rightOption, "rightAlt"), (.rightCommand, "rightGui"),
    ]

    /// Oryx's object of eight booleans (`leftCtrl` … `rightGui`); missing means false.
    public init(from decoder: Decoder) throws {
        let flags = try decoder.singleValueContainer().decode([String: Bool?].self)
        self = []
        for (m, name) in Self.names where flags[name] == true { insert(m) }
    }

    public func encode(to encoder: Encoder) throws {
        var flags: [String: Bool] = [:]
        for (m, name) in Self.names where contains(m) { flags[name] = true }
        var c = encoder.singleValueContainer()
        try c.encode(flags)
    }
}

extension Macro: Codable {
    private enum Keys: String, CodingKey { case keys, name, endEnter, applyAlt }
    private struct Step: Codable {
        var code: String?
        var delay: Int?
        var modifiers: Modifiers?
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let steps = try c.decodeIfPresent([Step].self, forKey: .keys) ?? []
        self.init(
            name: try c.decodeIfPresent(String.self, forKey: .name),
            steps: steps.compactMap { s in s.code.map { MacroStep(code: $0, modifiers: s.modifiers ?? [], delay: s.delay ?? 0) } },
            endsWithEnter: try c.decodeIfPresent(Bool.self, forKey: .endEnter) ?? false,
            holdsOption: try c.decodeIfPresent(Bool.self, forKey: .applyAlt) ?? false)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(
            steps.map { Step(code: $0.code, delay: $0.delay, modifiers: $0.modifiers.isEmpty ? nil : $0.modifiers) },
            forKey: .keys)
        try c.encodeIfPresent(name, forKey: .name)
        if endsWithEnter { try c.encode(true, forKey: .endEnter) }
        if holdsOption { try c.encode(true, forKey: .applyAlt) }
    }
}

extension Combo: Codable {
    private enum Keys: String, CodingKey { case name, layerIdx, keyIndices, trigger }

    /// Oryx stores the output as a whole key in `trigger`; Sextant keeps its tap. The id is assigned by position.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        self.init(
            id: "combo",
            name: try c.decodeIfPresent(String.self, forKey: .name),
            keyIndices: try c.decodeIfPresent([Int].self, forKey: .keyIndices) ?? [],
            layer: try c.decodeIfPresent(Int.self, forKey: .layerIdx),
            output: try c.decodeIfPresent(Key.self, forKey: .trigger)?.tap ?? .none)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(layer, forKey: .layerIdx)
        try c.encode(keyIndices, forKey: .keyIndices)
        try c.encode(Key(tap: output), forKey: .trigger)
    }
}

/// One side of Oryx's `navigators` object: `kind` plus options. Null options are dropped (null means default).
private struct NavigatorOptions: Codable {
    var kind: String?
    var options: [String: SettingValue]

    init(_ config: NavigatorConfig) {
        kind = config.kind.rawValue
        options = config.options
    }

    func config(side: NavigatorConfig.Side) -> NavigatorConfig? {
        guard let kind = kind.flatMap(NavigatorConfig.Kind.init(rawValue:)) else { return nil }
        return NavigatorConfig(kind: kind, side: side, options: options)
    }

    init(from decoder: Decoder) throws {
        let all = try LenientDictionary(from: decoder).values
        kind = all["kind"].flatMap { if case let .text(s) = $0 { s } else { nil } }
        options = all.filter { $0.key != "kind" }
    }

    func encode(to encoder: Encoder) throws {
        var all = options
        all["kind"] = kind.map(SettingValue.text)
        try all.encode(to: encoder)
    }
}

/// A JSON object whose values are kept when they decode as ``SettingValue`` and skipped otherwise (nulls, objects).
private struct LenientDictionary: Decodable {
    var values: [String: SettingValue]

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        var out: [String: SettingValue] = [:]
        for k in c.allKeys {
            if let v = try? c.decode(SettingValue.self, forKey: k) { out[k.stringValue] = v }
        }
        values = out
    }
}

/// A colour that decodes to nil instead of failing when Oryx stores something that isn't `#RRGGBB`.
private struct LenientColor: Decodable {
    var color: HexColor?
    init(from decoder: Decoder) throws {
        color = (try? decoder.singleValueContainer().decode(String.self)).flatMap(HexColor.init(hex:))
    }
}
