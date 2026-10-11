import Foundation

/// Errors from ``KeyboardLayout/init(oryxJSON:)``.
public enum OryxDecodingError: Error, CustomStringConvertible {
    case missingRevision
    case badLayerKeyCount(layer: String, count: Int)

    public var description: String {
        switch self {
        case .missingRevision: "The JSON has no layout revision."
        case let .badLayerKeyCount(layer, count): "Layer \(layer) has \(count) keys."
        }
    }
}

extension KeyboardLayout {
    /// Decodes Oryx's GraphQL layout JSON (`{"data":{"layout":{…,"revision":{…}}}}`), the format of
    /// `docs/research/oryx-examples/*.json`. Also accepts the bare `layout` object.
    ///
    /// - Oryx's `KeyStep.modifier` (`MOD_LSFT`) and `modifiers` (8 bools) both fold into ``KeyAction/modifiers``.
    /// - Leaked UI-state fields (`swapped`, `pristine`, `history`, …) are ignored.
    /// - `config` keeps only scalar/array values, as ``SettingValue``.
    public init(oryxJSON data: Data) throws {
        let decoder = JSONDecoder()
        let raw: OryxRaw.RawLayout
        if let env = try? decoder.decode(OryxRaw.Envelope.self, from: data) {
            raw = env.data.layout
        } else {
            raw = try decoder.decode(OryxRaw.RawLayout.self, from: data)
        }
        guard let rev = raw.revision else { throw OryxDecodingError.missingRevision }
        let layers = (rev.layers ?? [])
            .sorted { ($0.position ?? 0) < ($1.position ?? 0) }
            .map { l in
                Layer(id: l.hashId ?? UUID().uuidString, title: l.title ?? "Layer", color: l.color.flatMap(HexColor.init(hex:)),
                      keys: (l.keys ?? []).map { $0?.model ?? .transparent })
            }
        let combos: [Combo] = (rev.combos ?? []).enumerated().map { i, c in
            Combo(id: "combo-\(i)", name: c.name, keyIndices: c.keyIndices ?? [], layer: c.layerIdx, output: c.trigger?.tap?.model ?? KeyAction.none)
        }
        var navigator: NavigatorConfig?
        for (side, n) in [(NavigatorConfig.Side.left, rev.navigators?.left), (.right, rev.navigators?.right)] {
            guard let n, let kind = n.kind.flatMap(NavigatorConfig.Kind.init(rawValue:)) else { continue }
            navigator = NavigatorConfig(kind: kind, side: side, options: n.options)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        self.init(id: raw.hashId ?? "local", revisionId: rev.hashId ?? "draft", title: raw.title ?? "Untitled Layout",
                  geometry: raw.geometry ?? "voyager", firmwareVersion: rev.qmkVersion, revisionMessage: rev.title,
                  createdAt: rev.createdAt.flatMap { formatter.date(from: $0) }, md5: rev.md5,
                  layers: layers, combos: combos, settings: rev.config?.values ?? [:], navigator: navigator)
    }

    /// Loads a layout from an Oryx JSON file on disk.
    public init(oryxFile url: URL) throws {
        try self.init(oryxJSON: Data(contentsOf: url))
    }
}

/// Raw Oryx shapes. Internal: decode with ``KeyboardLayout/init(oryxJSON:)``.
enum OryxRaw {
    struct Envelope: Decodable { var data: DataBox }
    struct DataBox: Decodable { var layout: RawLayout }

    struct RawLayout: Decodable {
        var hashId: String?
        var title: String?
        var geometry: String?
        var revision: Revision?
    }

    struct Revision: Decodable {
        var hashId: String?
        var qmkVersion: String?
        var title: String?
        var createdAt: String?
        var md5: String?
        var config: Config?
        var layers: [Layer]?
        var combos: [RawCombo]?
        var navigators: Navigators?
    }

    struct Layer: Decodable {
        var hashId: String?
        var title: String?
        var position: Int?
        var color: String?
        var keys: [RawKey?]?
    }

    struct RawCombo: Decodable {
        var name: String?
        var layerIdx: Int?
        var keyIndices: [Int]?
        var trigger: RawKey?
    }

    struct Navigators: Decodable {
        var left: Navigator?
        var right: Navigator?
    }

    struct Navigator: Decodable {
        var kind: String?
        var options: [String: SettingValue]
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            kind = try? c.decode(String.self, forKey: AnyKey("kind"))
            var opts: [String: SettingValue] = [:]
            for k in c.allKeys where k.stringValue != "kind" {
                if let v = try? c.decode(SettingValue.self, forKey: k) { opts[k.stringValue] = v }
            }
            options = opts
        }
    }

    struct Config: Decodable {
        var values: [String: SettingValue]
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            var out: [String: SettingValue] = [:]
            for k in c.allKeys {
                if let v = try? c.decode(SettingValue.self, forKey: k) { out[k.stringValue] = v }
            }
            values = out
        }
    }

    struct RawModifiers: Decodable {
        var leftCtrl, leftShift, leftAlt, leftGui, rightCtrl, rightShift, rightAlt, rightGui: Bool?
        var model: Modifiers {
            var m: Modifiers = []
            if leftCtrl == true { m.insert(.leftControl) }
            if leftShift == true { m.insert(.leftShift) }
            if leftAlt == true { m.insert(.leftOption) }
            if leftGui == true { m.insert(.leftCommand) }
            if rightCtrl == true { m.insert(.rightControl) }
            if rightShift == true { m.insert(.rightShift) }
            if rightAlt == true { m.insert(.rightOption) }
            if rightGui == true { m.insert(.rightCommand) }
            return m
        }
    }

    struct RawMacroKey: Decodable {
        var code: String?
        var delay: Int?
        var modifiers: RawModifiers?
    }

    struct RawMacro: Decodable {
        var keys: [RawMacroKey]?
        var name: String?
        var applyAlt: Bool?
        var endEnter: Bool?
    }

    struct RawStep: Decodable {
        var code: String?
        var layer: Int?
        var modifier: String?
        var modifiers: RawModifiers?
        var macro: RawMacro?
        var color: String?
        var description: String?

        var model: KeyAction? {
            guard let code else { return nil }
            var mods = modifiers?.model ?? []
            if let m = modifier.flatMap(Modifiers.init(qmkMask:)) { mods.formUnion(m) }
            let macroModel = macro.map { m in
                Macro(name: m.name,
                      steps: (m.keys ?? []).compactMap { k in k.code.map { MacroStep(code: $0, modifiers: k.modifiers?.model ?? [], delay: k.delay ?? 0) } },
                      endsWithEnter: m.endEnter ?? false, holdsOption: m.applyAlt ?? false)
            }
            return KeyAction(code: code, layer: layer, modifiers: mods, macro: macroModel,
                             color: color.flatMap(HexColor.init(hex:)), description: description)
        }
    }

    struct RawKey: Decodable {
        var tap, hold, doubleTap, tapHold: RawStep?
        var customLabel: String?
        var glowColor: String?
        var tappingTerm: Int?

        var model: Key {
            Key(tap: tap?.model, hold: hold?.model, doubleTap: doubleTap?.model, tapHold: tapHold?.model,
                customLabel: customLabel?.isEmpty == true ? nil : customLabel,
                glowColor: glowColor.flatMap(HexColor.init(hex:)), tappingTerm: tappingTerm)
        }
    }

    struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ s: String) { stringValue = s }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}
