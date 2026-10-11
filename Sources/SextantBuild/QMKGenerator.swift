import Foundation
import SextantApplication
import SextantDomain

/// Generates Oryx-equivalent QMK source for the ZSA Voyager (research 02 §4): `keymap.c`, `config.h`, `rules.mk`,
/// `keymap.json` and, when the layout uses locale or OS-shortcut codes, `i18n.h`.
///
/// The output follows the sources Oryx generates for firmware 25 (golden-tested against five of them), keeps the
/// `zsa/oryx` and `zsa/defaults` modules and the Navigator modules, and maps every key-specific `keymap.c` line back
/// to its key. Layouts it can't express exactly fail with ``GeneratorError/unsupported(_:_:)`` instead of building
/// firmware that silently differs from the layout.
public struct QMKGenerator: FirmwareGenerator {
    public init() {}

    public func generate(_ layout: KeyboardLayout, identity: FirmwareIdentity) throws(GeneratorError) -> GeneratedSource {
        guard let board = layout.board, board == .voyager else { throw .unsupportedBoard(layout.geometry) }
        guard layout.layers.count <= 32 else { throw .unsupported(String(localized: "more than 32 layers"), nil) }
        let plan = try KeymapPlan(layout)
        let features = try Features(plan)
        let keymap = KeymapSource(plan: plan, features: features, board: board).render()
        var files = [
            "keymap.c": keymap.text,
            "config.h": features.configH(serial: identity.serial),
            "rules.mk": features.rulesMk(),
            "keymap.json": features.keymapJSON(),
        ]
        if !plan.localeCodes.isEmpty {
            files["i18n.h"] =
                plan.localeCodes.compactMap { code in QMKCodes.locale[code].map { "#define \(code) \($0)" } }
                .joined(separator: "\n") + "\n"
        }
        return GeneratedSource(files: files, sourceMap: keymap.sourceMap)
    }
}

/// The first pass over a layout: each key's `keymap.c` token, and everything the tokens refer to (dual-function keys,
/// tap dances, macros, colour keys, locale codes), numbered the way Oryx numbers them: by layer, then key index.
struct KeymapPlan {
    struct DualFunction {
        var key: KeyRef
        var tap: KeyAction
        var hold: KeyAction
        /// A unique `LT()` keycode so QMK runs its tap/hold engine; `process_record_user` does the actions, so its
        /// layer and keycode are never used.
        var placeholder = ""
    }
    struct Dance {
        var key: KeyRef
        var slots: Key
    }
    struct MacroUse {
        var macro: Macro
        var key: KeyRef?
    }
    struct ColorKey {
        var name: String
        var hsv: QMKCodes.HSV
        var key: KeyRef?
    }
    struct ComboKeys {
        var keys: [String]
        var output: String
    }

    let layout: KeyboardLayout
    /// `[layer][Oryx index]`.
    private(set) var tokens: [[String]] = []
    private(set) var dualFunctions: [DualFunction] = []
    private(set) var dances: [Dance] = []
    private(set) var macros: [MacroUse] = []
    private(set) var colors: [ColorKey] = []
    private(set) var combos: [ComboKeys] = []
    /// Locale and OS-shortcut codes `i18n.h` must define, in first-use order.
    private(set) var localeCodes: [String] = []
    /// Canonical codes of every key and combo action, for feature switches.
    private(set) var codes: Set<String> = []

    init(_ layout: KeyboardLayout) throws(GeneratorError) {
        self.layout = layout
        for (li, layer) in layout.layers.enumerated() {
            var row: [String] = []
            for (ki, key) in layer.keys.enumerated() { row.append(try token(for: key, at: KeyRef(layer: li, index: ki))) }
            tokens.append(row)
        }
        let used = Set(tokens.joined())
        let codes = (13...24).map { "KC_F\($0)" } + "ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890".map { "KC_\($0)" }
        let placeholders = (0...15).reversed().flatMap { layer in codes.map { "LT(\(layer), \($0))" } }.filter { !used.contains($0) }
        guard placeholders.count >= dualFunctions.count else {
            throw .unsupported(String(localized: "more than \(placeholders.count) dual-function keys"), nil)
        }
        for i in dualFunctions.indices { dualFunctions[i].placeholder = placeholders[i] }
        // Oryx's combos are keycode-based: each lists the tokens on its layer at its key indices.
        for combo in layout.combos where !combo.keyIndices.isEmpty {
            let layer = combo.layer ?? 0
            var keys: [String] = []
            for index in combo.keyIndices {
                guard tokens.indices.contains(layer), tokens[layer].indices.contains(index) else {
                    throw .unsupported(String(localized: "a combo with a key that isn't on the keyboard"), nil)
                }
                keys.append(tokens[layer][index])
            }
            note(combo.output)
            combos.append(ComboKeys(keys: keys, output: try expression(combo.output, at: nil)))
        }
    }

    private mutating func token(for key: Key, at ref: KeyRef) throws(GeneratorError) -> String {
        for (_, action) in key.actions { note(action) }
        if key.isTransparent { return "KC_TRANSPARENT" }
        if key.doubleTap != nil || key.tapHold != nil {
            for (slot, action) in key.actions where QMKCodes.statements(action) == nil {
                throw Self.unsupportedPart(action, KeyRef(layer: ref.layer, index: ref.index, slot: slot))
            }
            if let tap = key.tap, !QMKCodes.isKeycode(tap) {
                throw .unsupported(
                    String(localized: "a tap dance whose tap isn't a key"), KeyRef(layer: ref.layer, index: ref.index, slot: .tap))
            }
            dances.append(Dance(key: ref, slots: key))
            return "TD(DANCE_\(dances.count - 1))"
        }
        switch (key.tap, key.hold) {
        case let (tap?, hold?):
            if let compact = QMKCodes.modTapOrLayerTap(tap: tap, hold: hold) { return compact }
            for (slot, action) in [(KeySlot.tap, tap), (.hold, hold)] where QMKCodes.statements(action) == nil {
                throw Self.unsupportedPart(action, KeyRef(layer: ref.layer, index: ref.index, slot: slot))
            }
            dualFunctions.append(DualFunction(key: ref, tap: tap, hold: hold))
            return "DUAL_FUNC_\(dualFunctions.count - 1)"
        case let (tap?, nil): return try expression(tap, at: ref)
        case let (nil, hold?): return try expression(hold, at: ref)
        case (nil, nil): return "KC_TRANSPARENT"
        }
    }

    /// The C expression for one action; registers the macro or colour key it needs.
    private mutating func expression(_ action: KeyAction, at ref: KeyRef?) throws(GeneratorError) -> String {
        if let macro = action.macro {
            macros.append(MacroUse(macro: macro, key: ref))
            return "ST_MACRO_\(macros.count - 1)"
        }
        switch action.canonicalCode {
        case "MO", "TG", "TO", "TT", "OSL", "DF", "LM":
            guard let layer = action.layer, layout.layers.indices.contains(layer) else {
                throw .unsupported(String(localized: "a layer key for a layer that doesn't exist"), ref)
            }
            return action.canonicalCode == "LM"
                ? "LM(\(layer),\(QMKCodes.mask(action.modifiers)))" : "\(action.code)(\(layer))"
        case "OSM": return "OSM(\(QMKCodes.mask(action.modifiers)))"
        case "RGB":
            guard let color = action.color else { throw .unsupported(String(localized: "a colour key without a colour"), ref) }
            let hsv = QMKCodes.HSV(color)
            let name = "HSV_\(hsv.h)_\(hsv.s)_\(hsv.v)"
            if !colors.contains(where: { $0.name == name }) { colors.append(ColorKey(name: name, hsv: hsv, key: ref)) }
            return name
        default: return QMKCodes.wrap(action.code, action.modifiers)
        }
    }

    private mutating func note(_ action: KeyAction) {
        codes.insert(action.canonicalCode)
        if QMKCodes.locale[action.code] != nil, !localeCodes.contains(action.code) { localeCodes.append(action.code) }
    }

    private static func unsupportedPart(_ action: KeyAction, _ ref: KeyRef) -> GeneratorError {
        let what = action.macro == nil ? "“\(action.code)”" : String(localized: "a macro")
        return .unsupported(String(localized: "\(what) as part of a dual-function or tap-dance key"), ref)
    }
}
