import Foundation
import SextantDomain

/// Macro edits (spec §6.3). Each is one named undo step that brings the selected macro and step back with it. Never log
/// a macro's steps: they can hold secrets.
extension EditSession {
    /// The selected macro, while it is still where the selection says.
    public var selectedMacro: Macro? { selection.macro.flatMap { layout.macro(at: $0) } }

    public func selectMacro(_ locator: MacroLocator?, step: Int? = nil) {
        selection.macro = locator
        selection.step = step
    }

    /// Makes an empty macro in the drafts and selects it.
    public func newMacro() {
        let id = UUID().uuidString
        edit(String(localized: "New Macro"), select: { Self.select(&$0, .draft(id), step: nil) }) { $0.addMacroDraft(id: id) }
    }

    /// Names a macro (``KeyboardLayout/renameMacro(at:to:)``); an empty name clears it.
    public func renameMacro(_ locator: MacroLocator, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        edit(String(localized: "Rename Macro")) { $0.renameMacro(at: locator, to: trimmed.isEmpty ? nil : trimmed) }
    }

    public func deleteMacro(_ locator: MacroLocator) {
        edit(
            String(localized: "Delete Macro"),
            select: { if $0.macro == locator { Self.select(&$0, nil, step: nil) } }
        ) { $0.removeMacro(at: locator) }
    }

    /// Inserts a step and selects it.
    public func insertStep(_ step: MacroStep, at index: Int, in locator: MacroLocator) {
        guard let count = layout.macro(at: locator)?.steps.count else { return }
        let at = min(max(index, 0), count)
        edit(String(localized: "Add Step"), select: { Self.select(&$0, locator, step: at) }) {
            $0.updateMacro(at: locator) { $0.insertStep(step, at: at) }
        }
    }

    public func deleteStep(at index: Int, in locator: MacroLocator) {
        guard let count = layout.macro(at: locator)?.steps.count, (0..<count).contains(index) else { return }
        // The step that takes its place, else the one before it.
        let next = count > 1 ? min(index, count - 2) : nil
        edit(String(localized: "Delete Step"), select: { Self.select(&$0, locator, step: next) }) {
            $0.updateMacro(at: locator) { $0.removeStep(at: index) }
        }
    }

    public func duplicateStep(at index: Int, in locator: MacroLocator) {
        edit(String(localized: "Duplicate Step"), select: { Self.select(&$0, locator, step: index + 1) }) {
            $0.updateMacro(at: locator) { $0.duplicateStep(at: index) }
        }
    }

    /// Moves a step before the one at `destination` (``Macro/moveStep(from:to:)``), keeping it selected.
    public func moveStep(from source: Int, to destination: Int, in locator: MacroLocator) {
        let landed = destination > source ? destination - 1 : destination
        edit(String(localized: "Move Step"), select: { Self.select(&$0, locator, step: landed) }) {
            $0.updateMacro(at: locator) { $0.moveStep(from: source, to: destination) }
        }
    }

    /// Sets the key a step presses, keeping its modifiers and adding `modifiers` (⇧ for a shifted symbol).
    public func setStepCode(_ code: String, adding modifiers: Modifiers = [], at index: Int, in locator: MacroLocator) {
        edit(String(localized: "Set Step Key")) {
            $0.updateMacro(at: locator) { macro in
                guard macro.steps.indices.contains(index) else { return }
                macro.steps[index].code = code
                macro.steps[index].modifiers.formUnion(modifiers)
            }
        }
    }

    public func setStepModifiers(_ modifiers: Modifiers, at index: Int, in locator: MacroLocator) {
        edit(String(localized: "Change Modifiers")) {
            $0.updateMacro(at: locator) { macro in if macro.steps.indices.contains(index) { macro.steps[index].modifiers = modifiers } }
        }
    }

    /// Sets the pause after a step, kept to 0…5000 ms.
    public func setStepDelay(_ delay: Int, at index: Int, in locator: MacroLocator) {
        edit(String(localized: "Set Wait")) { $0.updateMacro(at: locator) { $0.setDelay(delay, at: index) } }
    }

    public func setEndsWithEnter(_ on: Bool, in locator: MacroLocator) {
        edit(String(localized: "End with Return")) { $0.updateMacro(at: locator) { $0.endsWithEnter = on } }
    }

    public func setHoldsOption(_ on: Bool, in locator: MacroLocator) {
        edit(String(localized: "Hold Option While Typing")) { $0.updateMacro(at: locator) { $0.holdsOption = on } }
    }

    /// Puts the macro on a key's tap (``KeyboardLayout/assignMacro(at:layer:index:)``) and selects it there.
    public func assignMacro(_ locator: MacroLocator, layer: Int, index: Int) {
        var assigned: MacroLocator?
        edit(String(localized: "Assign Macro to Key"), select: { Self.select(&$0, assigned, step: nil) }) {
            assigned = $0.assignMacro(at: locator, layer: layer, index: index)
        }
    }

    /// Takes the macro off its key into the drafts, and selects the draft.
    public func unassignMacro(_ locator: MacroLocator) {
        let id = UUID().uuidString
        edit(String(localized: "Remove Macro from Key"), select: { Self.select(&$0, .draft(id), step: nil) }) {
            $0.unassignMacro(at: locator, draftID: id)
        }
    }

    /// Record Steps: inserts a recorded step and selects it. `pause` (ms), when given, becomes the wait after the step
    /// before it: the time between the two key presses.
    public func recordStep(_ step: MacroStep, pause: Int?, at index: Int, in locator: MacroLocator) {
        guard let count = layout.macro(at: locator)?.steps.count else { return }
        let at = min(max(index, 0), count)
        edit(String(localized: "Record Step"), select: { Self.select(&$0, locator, step: at) }) { doc in
            doc.updateMacro(at: locator) { macro in
                if let pause { macro.setDelay(pause, at: at - 1) }
                macro.insertStep(step, at: at)
            }
        }
    }

    private static func select(_ selection: inout EditorSelection, _ macro: MacroLocator?, step: Int?) {
        selection.macro = macro
        selection.step = step
    }
}
