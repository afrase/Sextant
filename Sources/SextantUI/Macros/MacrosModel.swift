import Accessibility
import Foundation
import Observation
import SextantApplication
import SextantDomain

/// The Macros page's own state (spec §6.3). The selected macro and step live in the session's selection, so undo brings
/// them back.
@MainActor
@Observable
final class MacrosModel {
    /// Record Steps while it listens; nil when off.
    var stepRecorder: StepRecorder?
    /// Record Steps keeps the time between two keys as the first one's wait.
    var recordsPauses = false
}

/// Words for macros: library rows, the editor's summary, the preview and VoiceOver (spec §6.3).
enum MacroText {
    /// The macro's name; else the label of its key (Oryx keeps a macro's name there); else what it types, in quotes.
    static func title(_ macro: Macro, at locator: MacroLocator? = nil, in layout: KeyboardLayout? = nil) -> String {
        if let name = macro.name, !name.isEmpty { return name }
        if case let .key(ref)? = locator, let label = layout?.key(layer: ref.layer, index: ref.index)?.customLabel { return label }
        let typed = macro.steps.map(step).joined()
        return typed.isEmpty ? String(localized: "Empty Macro") : "“\(typed)”"
    }

    /// "8 steps · 210 ms".
    static func stats(_ macro: Macro) -> String {
        let steps = macro.steps.count == 1 ? String(localized: "1 step") : String(localized: "\(macro.steps.count) steps")
        return "\(steps) · \(String(localized: "\(macro.totalDelay) ms"))"
    }

    /// Where it plays: "Brd+Sys · key 17", "Combo 2", or "not on a key yet".
    static func place(_ locator: MacroLocator, in layout: KeyboardLayout) -> String {
        switch locator {
        case let .key(ref):
            let place = String(localized: "\(layout.layers[safe: ref.layer]?.title ?? "") · key \(ref.index)")
            return ref.slot == .tap || ref.slot == nil ? place : "\(place) · \(ref.slot?.title ?? "")"
        case let .combo(id):
            let index = layout.combos.firstIndex { $0.id == id } ?? 0
            return layout.combos[safe: index]?.name ?? String(localized: "Combo \(index + 1)")
        case .draft: return String(localized: "not on a key yet")
        }
    }

    /// The editor's line: "8/24 steps · ≈0.29 s · plays on tap of Brd+Sys key 17". Each step counts 10 ms of key press.
    static func summary(_ macro: Macro, at locator: MacroLocator, in layout: KeyboardLayout) -> String {
        let seconds = (Double(macro.totalDelay + 10 * macro.steps.count) / 1000).formatted(.number.precision(.fractionLength(2)))
        let plays: String
        switch locator {
        case let .key(ref):
            let (slot, layer) = ((ref.slot ?? .tap).title.lowercased(), layout.layers[safe: ref.layer]?.title ?? "")
            plays = String(localized: "plays on \(slot) of \(layer) key \(ref.index)")
        case .combo: plays = String(localized: "plays from \(place(locator, in: layout))")
        case .draft: plays = String(localized: "not on a key yet")
        }
        return [String(localized: "\(macro.steps.count)/\(Macro.maxSteps) steps"), "≈\(seconds) s", plays].joined(separator: " · ")
    }

    /// The preview (spec §6.3): "⇧⌘O ⧗150 k e y m a p ⧗60 ⏎". The last wait shows only before the closing Return,
    /// as the firmware types it.
    static func typed(_ macro: Macro) -> String {
        var parts: [String] = []
        for (i, s) in macro.steps.enumerated() {
            parts.append(step(s))
            if s.delay > 0, i < macro.steps.count - 1 || macro.endsWithEnter { parts.append("⧗\(s.delay)") }
        }
        if macro.endsWithEnter { parts.append("⏎") }
        let text = parts.joined(separator: " ")
        return macro.holdsOption ? String(localized: "holding ⌥: \(text)") : text
    }

    /// One step as typed: a letter alone types lower case ("k"); a chord shows its glyphs ("⇧⌘O"); Space is "␣".
    static func step(_ step: MacroStep) -> String {
        if step.modifiers.isEmpty, step.code.wholeMatch(of: /KC_[A-Z]/) != nil { return step.code.suffix(1).lowercased() }
        if KeycodeCatalog.canonicalCode(step.code) == "KC_SPACE" { return step.modifiers.glyphs + "␣" }
        return Legends.legend(for: KeyAction(code: step.code, modifiers: step.modifiers)).text
    }

    /// What VoiceOver says for a step: "Step 3, Left Shift + Left Command + O, then wait 150 ms".
    static func spoken(_ step: MacroStep, index: Int) -> String {
        let name = Legends.legend(for: KeyAction(code: step.code, modifiers: step.modifiers)).name
        let wait = step.delay > 0 ? String(localized: ", then wait \(step.delay) ms") : ""
        return String(localized: "Step \(index + 1), \(name)\(wait)")
    }
}

extension LayoutWindowModel {
    /// Assign to Key… (spec §6.3): shows the board, where one click puts the macro on that key's tap. The page comes back
    /// when the pick ends; choosing another page or layout meanwhile drops the pick.
    public func assignMacroToKey(_ locator: MacroLocator) {
        guard let session, let macro = session.layout.macro(at: locator) else { return }
        let back: @MainActor () -> Void = { [weak self] in
            if let self, self.session === session, self.page == nil { self.destination = .macros }
        }
        let title = MacroText.title(macro, at: locator, in: session.layout)
        macros.stepRecorder = nil
        destination = .layer(session.selection.layer)
        boardPick = BoardPick(
            prompt: String(localized: "Click a key to play ‘\(title)’ on tap · esc cancels"),
            onPick: { index in
                // A layer deleted or moved meanwhile puts another macro, or none, where this one was.
                if session.layout.macro(at: locator) == macro { session.assignMacro(locator, layer: session.selection.layer, index: index) }
                back()
                return true
            },
            onCancel: back)
    }

    /// The step's key tile, or Add Step with no step: the picker, offering only codes a step can type (ADR 0042).
    public func openStepPicker(step index: Int?, in locator: MacroLocator) {
        guard let session, let macro = session.layout.macro(at: locator) else { return }
        let title = MacroText.title(macro, at: locator, in: session.layout)
        let step = index.flatMap { macro.steps[safe: $0] }
        let target = AssignTarget(
            title: index.map { String(localized: "\(title) › Step \($0 + 1)") } ?? String(localized: "\(title) › New Step"),
            current: step.map { KeyAction(code: $0.code, modifiers: $0.modifiers) },
            accepts: { $0.macro == nil && MacroStep.typing($0.code) != nil }
        ) { action in
            guard let typed = MacroStep.typing(action.code) else { return }
            if let index {
                session.setStepCode(typed.code, adding: typed.modifiers, at: index, in: locator)
            } else {
                // After the selected step, else at the end.
                let after = session.selection.macro == locator ? session.selection.step.map { $0 + 1 } : nil
                session.insertStep(typed, at: after ?? macro.steps.count, in: locator)
            }
        }
        openKeycodePicker(target)
    }

    /// Record Steps (spec §6.3) into a macro; esc stops it. It ends Record Key and closes the picker.
    public func startRecordingSteps(in locator: MacroLocator) {
        palette = nil
        recorder = nil
        macros.stepRecorder = StepRecorder(macro: locator)
    }

    func stopRecordingSteps() { macros.stepRecorder = nil }

    /// The picker's Macros category: the library. On the selected key's tap a choice goes there as Assign to Key puts it;
    /// another target (a combo's output) gets a copy.
    func macroPickerItems(_ query: String) -> [PaletteItem] {
        guard let session else { return [] }
        let layout = session.layout
        let target = assignTarget
        let isKeySlot = palette?.target == nil
        return pickableMacros.compactMap { entry in
            let title = MacroText.title(entry.macro, at: entry.locator, in: layout)
            let action = KeyAction(code: "KC_TRANSPARENT", macro: entry.macro)
            guard query.isEmpty || PaletteSearch.score(query, [title]) > 0 else { return nil }
            // The cap shows the title: an unnamed macro's cap would say only "Macro".
            var shown = layout
            var named = entry.macro
            named.name = title
            shown.updateKey(layer: 0, index: 0) { $0 = Key(tap: KeyAction(code: "KC_TRANSPARENT", macro: named)) }
            return PaletteItem(
                id: "macro-\(entry.locator)", group: .keycodes, title: title, detail: MacroText.stats(entry.macro),
                note: MacroText.place(entry.locator, in: layout), leading: .cap(KeyCapModel(layout: shown, layer: 0, index: 0)),
                isCurrent: target?.current?.macro == entry.macro
            ) { [weak self] in
                if isKeySlot, target?.key != nil {
                    // Every selected key's tap (ADR 0047).
                    session.assignMacroToSelectedKeys(entry.locator)
                } else {
                    target?.assign(action)
                }
                self?.palette = nil
            }
        }
    }

    /// The rail's count for Macros, without building the rows.
    var macroPickerCount: Int { pickableMacros.count }

    /// The library macros the open target takes: a macro step takes none, and of the selected key's slots only the tap
    /// takes one, since a macro plays only from a tap (ADR 0042).
    private var pickableMacros: [LibraryMacro] {
        if palette?.target == nil, session?.selection.slot != .tap { return [] }
        let accepts = assignTarget?.accepts ?? { _ in true }
        return session?.layout.macros.filter { accepts(KeyAction(code: "KC_TRANSPARENT", macro: $0.macro)) } ?? []
    }

    /// ⌘K's Documents group (spec §5.7): macros by title, and all of them for "macro". One opens on the Macros page.
    func macroDocumentItems(_ query: String) -> [PaletteItem] {
        guard let session, !query.isEmpty else { return [] }
        let layout = session.layout
        let hits = layout.macros.compactMap { entry -> (score: Int, item: PaletteItem)? in
            let title = MacroText.title(entry.macro, at: entry.locator, in: layout)
            let score = PaletteSearch.score(query, [title, String(localized: "Macro")])
            guard score > 0 else { return nil }
            let item = PaletteItem(
                id: "document-macro-\(entry.locator)", group: .documents, title: title, detail: MacroText.stats(entry.macro),
                note: MacroText.place(entry.locator, in: layout), leading: .symbol("list.bullet.rectangle")
            ) { [weak self] in
                self?.palette = nil
                self?.destination = .macros
                session.selectMacro(entry.locator)
            }
            return (score, item)
        }
        return hits.enumerated().sorted { ($0.element.score, $1.offset) > ($1.element.score, $0.offset) }.prefix(5).map(\.element.item)
    }

    /// Show Key on an issue in a key's macro (a step that can't be typed): the macro on the Macros page, at its first such
    /// step, since the board can't edit steps. False when the slot holds no macro.
    func showMacroIssue(_ key: KeyRef) -> Bool {
        guard let session, let macro = session.layout.macro(at: .key(key)) else { return false }
        destination = .macros
        session.selectMacro(.key(key), step: macro.steps.firstIndex { !MacroStep.canType($0.code) })
        return true
    }

    /// Announces a change VoiceOver wouldn't otherwise hear.
    func announce(_ text: String) { AccessibilityNotification.Announcement(text).post() }
}
