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
        guard (1...32).contains(layout.layers.count), layout.layers.allSatisfy({ $0.keys.count == board.keyCount }) else {
            throw .unsupported(String(localized: "this number of layers or keys"), nil)
        }
        // The serial lands in a C string literal; Oryx's are `layout/revision` ids. zsa/oryx copies it, its NUL and a
        // stop byte into a 32-byte reply from offset 1, so it can't exceed 30 characters.
        guard identity.serial.utf8.count <= 30, identity.serial.wholeMatch(of: /[A-Za-z0-9\/._-]+/) != nil else {
            throw .unsupported(String(localized: "the firmware serial “\(identity.serial)”"), nil)
        }
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
            try note(combo.output, at: nil)
            combos.append(ComboKeys(keys: keys, output: try expression(combo.output, at: nil)))
        }
    }

    private mutating func token(for key: Key, at ref: KeyRef) throws(GeneratorError) -> String {
        for (slot, action) in key.actions { try note(action, at: KeyRef(layer: ref.layer, index: ref.index, slot: slot)) }
        if let term = key.tappingTerm, !KeyboardLayout.tappingTermRange.contains(term) {
            throw .unsupported(String(localized: "a tapping term of \(term) ms"), ref)
        }
        if key.isTransparent { return "KC_TRANSPARENT" }
        if key.doubleTap != nil || key.tapHold != nil { return try dance(key, at: ref) }
        switch (key.tap, key.hold) {
        case let (tap?, hold?):
            if let compact = QMKCodes.modTapOrLayerTap(tap: tap, hold: hold) { return compact }
            // Oryx built these as tap dances before it had dual-function keys; the setting keeps that (ADR 0040).
            if layout.settings["legacyDualFunctionDances"] == .bool(true) { return try dance(key, at: ref) }
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

    /// A tap dance for a key whose every action can run in one and whose tap is a key (``TapDanceSource``).
    private mutating func dance(_ key: Key, at ref: KeyRef) throws(GeneratorError) -> String {
        for (slot, action) in key.actions where !action.runsInTapDance {
            throw Self.unsupportedPart(action, KeyRef(layer: ref.layer, index: ref.index, slot: slot))
        }
        if let tap = key.tap, !tap.typesInTapDance {
            throw .unsupported(
                String(localized: "a tap dance whose tap isn't a key"), KeyRef(layer: ref.layer, index: ref.index, slot: .tap))
        }
        dances.append(Dance(key: ref, slots: key))
        return "TD(DANCE_\(dances.count - 1))"
    }

    /// The C expression for one action; registers the macro or colour key it needs.
    private mutating func expression(_ action: KeyAction, at ref: KeyRef?) throws(GeneratorError) -> String {
        if let macro = action.macro {
            // `SS_TAP(X_…)` with a code that has no `X_` name would not compile (ADR 0042).
            if let step = macro.steps.first(where: { !MacroStep.canType($0.code) }) {
                throw .unsupported(String(localized: "“\(step.code)” as a macro step"), ref)
            }
            macros.append(MacroUse(macro: macro, key: ref))
            return "ST_MACRO_\(macros.count - 1)"
        }
        switch action.canonicalCode {
        // note(_:at:) refused layer keys without a layer.
        case "MO", "TG", "TO", "TT", "OSL", "DF": return "\(action.code)(\(action.layer ?? 0))"
        case "LM":
            // QMK's LM() keeps only 4 bits of the layer.
            guard let layer = action.layer, layer < 16 else {
                throw .unsupported(String(localized: "a layer-with-modifiers key for a layer after the first 16"), ref)
            }
            return "LM(\(layer),\(QMKCodes.mask(action.modifiers)))"
        // ALL_T() and MEH_T() are function-like macros; a lone Hyper or Meh is the plain keycode.
        case "ALL_T": return QMKCodes.wrap("KC_HYPR", action.modifiers)
        case "MEH_T": return QMKCodes.wrap("KC_MEH", action.modifiers)
        case "OSM": return "OSM(\(QMKCodes.mask(action.modifiers)))"
        case "RGB":
            guard let color = action.color else { throw .unsupported(String(localized: "a color key without a color"), ref) }
            let hsv = QMKCodes.HSV(color)
            let name = "HSV_\(hsv.h)_\(hsv.s)_\(hsv.v)"
            if !colors.contains(where: { $0.name == name }) { colors.append(ColorKey(name: name, hsv: hsv, key: ref)) }
            return name
        default: return QMKCodes.wrap(action.code, action.modifiers)
        }
    }

    /// Checks an action from the layout (imported JSON is untrusted: its codes are pasted into C) and records its code.
    private mutating func note(_ action: KeyAction, at ref: KeyRef?) throws(GeneratorError) {
        for code in [action.code] + (action.macro?.steps.map(\.code) ?? []) where code.wholeMatch(of: /[A-Za-z_][A-Za-z0-9_]*/) == nil {
            throw .unsupported(String(localized: "“\(code)”, which isn't a keycode"), ref)
        }
        // SS_DELAY() blocks the keyboard's main loop: keep to Oryx's 0...5000 ms (research 01 §7).
        if let step = action.macro?.steps.first(where: { !(0...5000).contains($0.delay) }) {
            throw .unsupported(String(localized: "a macro pause of \(step.delay) ms"), ref)
        }
        if KeycodeCatalog.layerFunctions.contains(action.canonicalCode), !layout.layers.indices.contains(action.layer ?? -1) {
            throw .unsupported(String(localized: "a layer key for a layer that doesn't exist"), ref)
        }
        // Oryx-only codes this generator doesn't define yet.
        if action.code.hasPrefix("MAC_") || action.code.hasPrefix("ORYX_SL_") {
            throw .unsupported(String(localized: "the “\(action.code)” key"), ref)
        }
        // Without the setting, rules.mk compiles Space Cadet's handler out.
        if action.canonicalCode.hasPrefix("SC_"), layout.settings["enableSpaceCadet"]?.boolValue != true {
            throw .unsupported(String(localized: "“\(action.code)” while Space Cadet keys are off"), ref)
        }
        if action.canonicalCode.hasPrefix("AS_"), layout.settings["autoshift"]?.boolValue != true {
            throw .unsupported(String(localized: "“\(action.code)” while Auto Shift is off"), ref)
        }
        codes.insert(action.canonicalCode)
        if QMKCodes.locale[action.code] != nil, !localeCodes.contains(action.code) { localeCodes.append(action.code) }
    }

    private static func unsupportedPart(_ action: KeyAction, _ ref: KeyRef) -> GeneratorError {
        let what = action.macro == nil ? "“\(action.code)”" : String(localized: "a macro")
        return .unsupported(String(localized: "\(what) as part of a dual-function or tap-dance key"), ref)
    }
}
