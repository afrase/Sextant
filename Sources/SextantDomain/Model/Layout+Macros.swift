import Foundation

/// A macro on no key yet (spec §6.3 "not on a key yet"). Oryx's shape keeps macros only on keys and combo outputs, so
/// the layout keeps these in a field of its own, written only when there are some (ADR 0042).
public struct MacroDraft: Identifiable, Hashable, Sendable, Codable {
    public var id: String
    public var macro: Macro

    public init(id: String = UUID().uuidString, macro: Macro) {
        self.id = id
        self.macro = macro
    }
}

/// Where a macro lives. A macro on several keys is a copy on each, as in Oryx.
public enum MacroLocator: Hashable, Sendable {
    /// A key's slot; the slot is always set.
    case key(KeyRef)
    /// A combo's output, by the combo's id.
    case combo(String)
    /// A draft, by its id.
    case draft(String)
}

/// One macro in the layout's library.
public struct LibraryMacro: Hashable, Sendable, Identifiable {
    public var locator: MacroLocator
    public var macro: Macro
    public var id: MacroLocator { locator }
}

extension KeyboardLayout {
    /// The macro library (spec §6.3): macros on keys in layer, key and slot order, then on combos, then the drafts.
    public var macros: [LibraryMacro] {
        var out: [LibraryMacro] = []
        for (li, layer) in layers.enumerated() {
            for (ki, key) in layer.keys.enumerated() {
                for (slot, action) in key.actions {
                    if let macro = action.macro {
                        out.append(LibraryMacro(locator: .key(KeyRef(layer: li, index: ki, slot: slot)), macro: macro))
                    }
                }
            }
        }
        out += combos.compactMap { combo in combo.output.macro.map { LibraryMacro(locator: .combo(combo.id), macro: $0) } }
        return out + macroDrafts.map { LibraryMacro(locator: .draft($0.id), macro: $0.macro) }
    }

    /// The macro at `locator`; nil when there is none there.
    public func macro(at locator: MacroLocator) -> Macro? {
        switch locator {
        case let .key(ref): ref.slot.flatMap { key(layer: ref.layer, index: ref.index)?[$0]?.macro }
        case let .combo(id): combos.first { $0.id == id }?.output.macro
        case let .draft(id): macroDrafts.first { $0.id == id }?.macro
        }
    }

    /// Edits the macro at `locator`; does nothing when there is none.
    public mutating func updateMacro(at locator: MacroLocator, _ body: (inout Macro) -> Void) {
        switch locator {
        case let .key(ref):
            guard let slot = ref.slot else { return }
            updateKey(layer: ref.layer, index: ref.index) { key in
                if var macro = key[slot]?.macro {
                    body(&macro)
                    key[slot]?.macro = macro
                }
            }
        case let .combo(id):
            guard let i = combos.firstIndex(where: { $0.id == id }), var macro = combos[i].output.macro else { return }
            body(&macro)
            combos[i].output.macro = macro
        case let .draft(id):
            guard let i = macroDrafts.firstIndex(where: { $0.id == id }) else { return }
            body(&macroDrafts[i].macro)
        }
    }

    /// Adds `macro` to the drafts; returns where it is.
    @discardableResult
    public mutating func addMacroDraft(_ macro: Macro = Macro(steps: []), id: String = UUID().uuidString) -> MacroLocator {
        macroDrafts.append(MacroDraft(id: id, macro: macro))
        return .draft(id)
    }

    /// Removes the macro: its key slot empties (a key left with nothing turns transparent), a combo's output becomes
    /// `KC_NO` (an empty combo the issues flag), and a draft goes.
    public mutating func removeMacro(at locator: MacroLocator) {
        guard macro(at: locator) != nil else { return }
        switch locator {
        case let .key(ref):
            guard let slot = ref.slot else { return }
            updateKey(layer: ref.layer, index: ref.index) { key in
                key[slot] = nil
                if key.filledSlots.isEmpty { key.tap = .transparent }
            }
        case let .combo(id):
            if let i = combos.firstIndex(where: { $0.id == id }) { combos[i].output = .none }
        case let .draft(id):
            macroDrafts.removeAll { $0.id == id }
        }
    }

    /// Puts the macro on a key's tap and clears the key's other slots: the generator plays a macro only from a key's
    /// tap, never inside a dual-function key or a tap dance. A draft moves; a macro on a key or combo is copied, as Oryx
    /// keeps a copy per key. Returns the macro's new place, or nil when there is no such macro or key.
    @discardableResult
    public mutating func assignMacro(at locator: MacroLocator, toKey layer: Int, index: Int) -> MacroLocator? {
        guard let macro = movableMacro(at: locator), key(layer: layer, index: index) != nil else { return nil }
        if case .draft = locator { removeMacro(at: locator) }
        updateKey(layer: layer, index: index) { key in
            key.tap = KeyAction(code: "KC_TRANSPARENT", macro: macro)
            (key.hold, key.doubleTap, key.tapHold) = (nil, nil, nil)
        }
        return .key(KeyRef(layer: layer, index: index, slot: .tap))
    }

    /// Takes the macro off its key or combo into the drafts; returns the draft's place, or nil when there is no macro
    /// there (or it already is a draft).
    @discardableResult
    public mutating func unassignMacro(at locator: MacroLocator, draftID: String = UUID().uuidString) -> MacroLocator? {
        if case .draft = locator { return nil }
        guard let macro = movableMacro(at: locator) else { return nil }
        removeMacro(at: locator)
        return addMacroDraft(macro, id: draftID)
    }

    /// The macro as it leaves its key: an unnamed one takes the key's label as its name, since Oryx names macros by
    /// labelling their keys.
    private func movableMacro(at locator: MacroLocator) -> Macro? {
        guard var macro = macro(at: locator) else { return nil }
        if macro.name == nil, case let .key(ref) = locator { macro.name = key(layer: ref.layer, index: ref.index)?.customLabel }
        return macro
    }
}

extension Macro {
    /// The longest pause after a step: `SS_DELAY` blocks the keyboard's main loop, so Sextant keeps to Oryx's 5 s.
    public static let maxDelay = 5000

    /// Inserts a step; `index` is clamped to the steps.
    public mutating func insertStep(_ step: MacroStep, at index: Int) {
        steps.insert(step, at: min(max(index, 0), steps.count))
    }

    public mutating func removeStep(at index: Int) {
        if steps.indices.contains(index) { steps.remove(at: index) }
    }

    /// Puts a copy of the step right after it.
    public mutating func duplicateStep(at index: Int) {
        if steps.indices.contains(index) { steps.insert(steps[index], at: index + 1) }
    }

    /// Moves the step at `source` so it lands before the step that was at `destination` (`steps.count` moves it last),
    /// the way a drop between rows reads.
    public mutating func moveStep(from source: Int, to destination: Int) {
        guard steps.indices.contains(source), (0...steps.count).contains(destination) else { return }
        let step = steps.remove(at: source)
        steps.insert(step, at: destination > source ? destination - 1 : destination)
    }

    /// Sets the pause after a step, kept to 0…``maxDelay`` ms.
    public mutating func setDelay(_ delay: Int, at index: Int) {
        if steps.indices.contains(index) { steps[index].delay = min(max(delay, 0), Self.maxDelay) }
    }
}

extension MacroStep {
    /// True when QMK's `SEND_STRING` can type `code` as a step. It types each step by its `X_` name (`SS_TAP(X_A)`),
    /// which only HID keycodes have: layer keys, `QK_` codes, locale codes and Oryx's own codes have none, and would
    /// not compile (ADR 0042).
    public static func canType(_ code: String) -> Bool {
        code.hasPrefix("KC_") && typable.contains(String(code.dropFirst(3)))
    }

    /// Every `X_` name in the pinned QMK's `send_string_keycodes.h`, without the prefix.
    private static let typable = Set(
        """
        0 1 2 3 4 5 6 7 8 9 A ACL0 ACL1 ACL2 AGAIN AGIN ALGR ALTERNATE_ERASE APP APPLICATION ASSISTANT ASST AUDIO_MUTE AUDIO_VOL_DOWN
        AUDIO_VOL_UP B BACKSLASH BACKSPACE BRID BRIGHTNESS_DOWN BRIGHTNESS_UP BRIU BRK BRMD BRMU BSLS BSPC BTN1 BTN2 BTN3 BTN4 BTN5
        BTN6 BTN7 BTN8 C CALC CALCULATOR CANCEL CAPS CAPS_LOCK CLAG CLEAR CLEAR_AGAIN CLR CNCL COMM COMMA CONTROL_PANEL COPY CPNL CRSEL
        CRSL CUT D DEL DELETE DOT DOWN E EJCT END ENT ENTER EQL EQUAL ERAS ESC ESCAPE EXEC EXECUTE EXSEL EXSL F F1 F10 F11 F12 F13 F14
        F15 F16 F17 F18 F19 F2 F20 F21 F22 F23 F24 F3 F4 F5 F6 F7 F8 F9 FIND G GRAVE GRV H HELP HOME I INS INSERT INT1 INT2 INT3 INT4
        INT5 INT6 INT7 INT8 INT9 INTERNATIONAL_1 INTERNATIONAL_2 INTERNATIONAL_3 INTERNATIONAL_4 INTERNATIONAL_5 INTERNATIONAL_6
        INTERNATIONAL_7 INTERNATIONAL_8 INTERNATIONAL_9 J K KB_MUTE KB_POWER KB_VOLUME_DOWN KB_VOLUME_UP KP_0 KP_1 KP_2 KP_3 KP_4 KP_5
        KP_6 KP_7 KP_8 KP_9 KP_ASTERISK KP_COMMA KP_DOT KP_ENTER KP_EQUAL KP_EQUAL_AS400 KP_MINUS KP_PLUS KP_SLASH L LALT LANGUAGE_1
        LANGUAGE_2 LANGUAGE_3 LANGUAGE_4 LANGUAGE_5 LANGUAGE_6 LANGUAGE_7 LANGUAGE_8 LANGUAGE_9 LBRC LCAP LCMD LCTL LEFT LEFT_ALT
        LEFT_BRACKET LEFT_CTRL LEFT_GUI LEFT_SHIFT LGUI LNG1 LNG2 LNG3 LNG4 LNG5 LNG6 LNG7 LNG8 LNG9 LNUM LOCKING_CAPS_LOCK
        LOCKING_NUM_LOCK LOCKING_SCROLL_LOCK LOPT LSCR LSFT LWIN M MAIL MEDIA_EJECT MEDIA_FAST_FORWARD MEDIA_NEXT_TRACK
        MEDIA_PLAY_PAUSE MEDIA_PREV_TRACK MEDIA_REWIND MEDIA_SELECT MEDIA_STOP MENU MFFD MINS MINUS MNXT MPLY MPRV MRWD MS_ACCEL0
        MS_ACCEL1 MS_ACCEL2 MS_BTN1 MS_BTN2 MS_BTN3 MS_BTN4 MS_BTN5 MS_BTN6 MS_BTN7 MS_BTN8 MS_D MS_DOWN MS_L MS_LEFT MS_R MS_RIGHT
        MS_U MS_UP MS_WH_DOWN MS_WH_LEFT MS_WH_RIGHT MS_WH_UP MSEL MSTP MUTE MY_COMPUTER MYCM N NONUS_BACKSLASH NONUS_HASH NUBS NUHS
        NUM NUM_LOCK O OPER OUT P P0 P1 P2 P3 P4 P5 P6 P7 P8 P9 PAGE_DOWN PAGE_UP PAST PASTE PAUS PAUSE PCMM PDOT PENT PEQL PGDN PGUP
        PMNS PPLS PRINT_SCREEN PRIOR PRIR PSCR PSLS PSTE PWR Q QUOT QUOTE R RALT RBRC RCMD RCTL RETN RETURN RGHT RGUI RIGHT RIGHT_ALT
        RIGHT_BRACKET RIGHT_CTRL RIGHT_GUI RIGHT_SHIFT ROPT RSFT RWIN S SCLN SCRL SCROLL_LOCK SELECT SEMICOLON SEPARATOR SEPR SLASH
        SLCT SLEP SLSH SPACE SPC STOP SYRQ SYSTEM_POWER SYSTEM_REQUEST SYSTEM_SLEEP SYSTEM_WAKE T TAB U UNDO UP V VOLD VOLU W WAKE WBAK
        WFAV WFWD WH_D WH_L WH_R WH_U WHOM WREF WSCH WSTP WWW_BACK WWW_FAVORITES WWW_FORWARD WWW_HOME WWW_REFRESH WWW_SEARCH WWW_STOP X
        Y Z
        """.split(whereSeparator: \.isWhitespace).map(String.init))
}

extension LayoutIssues {
    /// Macro steps on keys and combos that `SEND_STRING` can't type, which the generator refuses. An unknown code is
    /// already `unknownKeycode`; drafts never reach the firmware.
    static func macroStepIssues(_ layout: KeyboardLayout) -> [LayoutIssue] {
        layout.macros.flatMap { entry -> [LayoutIssue] in
            let (key, combo): (KeyRef?, String?) =
                switch entry.locator {
                case let .key(ref): (ref, nil)
                case let .combo(id): (nil, id)
                case .draft: (nil, nil)
                }
            guard key != nil || combo != nil else { return [] }
            return entry.macro.steps.enumerated().compactMap { i, step in
                guard KeycodeCatalog.entry(for: step.code) != nil, !MacroStep.canType(step.code) else { return nil }
                return LayoutIssue(kind: .macroStepNotTypable(step: i, code: step.code), severity: .error, key: key, combo: combo)
            }
        }
    }
}
