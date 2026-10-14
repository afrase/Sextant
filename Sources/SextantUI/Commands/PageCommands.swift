import AppKit
import SextantApplication
import SextantDomain
import SwiftUI

/// The Combos and Macros pages' actions in the Edit menu and ⌘K (spec §9.1; §11: every action is reachable from a
/// menu). Each runs what the page's own control runs, and only on its page with something to act on. Delete is the
/// standard Edit ▸ Delete (``DeleteMenuItem``), which each page answers with `onDeleteCommand`.
extension LayoutWindowModel {
    /// New Combo, as N or the page's New Combo button; not during a board pick, which takes the board's clicks.
    var canStartNewCombo: Bool { page == .combos && session != nil && boardPick == nil }

    /// The combo Edit Combo Keys… would edit: the page's selected one, outside a board pick.
    var comboForKeys: String? { page == .combos && boardPick == nil ? selectedPageCombo?.id : nil }

    var canAddMacro: Bool { page == .macros && session != nil }

    /// The Macros page's selected macro, which Record Steps… and Assign to Key… act on.
    var pageMacro: MacroLocator? {
        guard page == .macros, let session, let locator = session.selection.macro, session.layout.macro(at: locator) != nil else {
            return nil
        }
        return locator
    }

    /// As the page's Record Steps button: a macro with room for a step, not already recording.
    var macroToRecordInto: MacroLocator? {
        guard let locator = pageMacro, let macro = session?.layout.macro(at: locator), macro.steps.count < Macro.maxSteps,
            macros.stepRecorder?.macro != locator
        else { return nil }
        return locator
    }

    /// ⌘K's rows for the page commands, in the Edit menu's order.
    func pagePaletteCommands(
        _ add: (_ title: String, _ shortcut: String, _ enabled: Bool, _ run: @escaping @MainActor () -> Void) -> Void
    ) {
        add(String(localized: "New Combo"), "", canStartNewCombo) { self.startNewCombo() }
        add(String(localized: "Edit Combo Keys…"), "", comboForKeys != nil) { if let id = self.comboForKeys { self.editComboKeys(id) } }
        add(String(localized: "Delete Combo"), "⌫", comboForKeys != nil) {
            if let id = self.comboForKeys { self.session?.deleteCombo(id) }
        }
        add(String(localized: "New Macro"), "", canAddMacro) { self.session?.newMacro() }
        add(String(localized: "Record Steps…"), "", macroToRecordInto != nil) {
            if let locator = self.macroToRecordInto { self.startRecordingSteps(in: locator) }
        }
        add(String(localized: "Assign to Key…"), "", pageMacro != nil) {
            if let locator = self.pageMacro { self.assignMacroToKey(locator) }
        }
        add(String(localized: "Delete Macro"), "⌫", pageMacro != nil) {
            if let locator = self.pageMacro { self.session?.deleteMacro(locator) }
        }
    }
}

/// Edit menu: the Combos page's items (spec §9.1).
struct ComboMenuItems: View {
    var window: LayoutWindowModel?

    var body: some View {
        Button("New Combo") { window?.startNewCombo() }.disabled(window?.canStartNewCombo != true)
        Button("Edit Combo Keys…") { if let id = window?.comboForKeys { window?.editComboKeys(id) } }
            .disabled(window?.comboForKeys == nil)
    }
}

/// Edit menu: the Macros page's items (spec §9.1).
struct MacroMenuItems: View {
    var window: LayoutWindowModel?

    var body: some View {
        Button("New Macro") { window?.session?.newMacro() }.disabled(window?.canAddMacro != true)
        Button("Record Steps…") { if let locator = window?.macroToRecordInto { window?.startRecordingSteps(in: locator) } }
            .disabled(window?.macroToRecordInto == nil)
        Button("Assign to Key…") { if let locator = window?.pageMacro { window?.assignMacroToKey(locator) } }
            .disabled(window?.pageMacro == nil)
    }
}

/// Edit ▸ Delete is AppKit's standard item, which SwiftUI enables for the focused view's `onDeleteCommand`: the selected
/// combo on the Combos page, the selected macro (or step) on the Macros page, the selection in a text field. It comes
/// with no key equivalent; this shows plain ⌫ on it, the key those views take (spec §9.1). The item never takes the key
/// itself: its equivalent is U+0008, and the Mac's ⌫ sends U+007F, which reaches the focused view as before.
@MainActor
public enum DeleteMenuItem {
    /// Shows ⌫ now and again each time a menu opens, in case SwiftUI rebuilt the menu bar.
    public static func showDeleteKey() {
        apply()
        // Unqueued, so it runs as tracking begins, before the menu draws.
        NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { _ in
            MainActor.assumeIsolated { apply() }
        }
    }

    static func apply() {
        for menu in NSApp.mainMenu?.items.compactMap(\.submenu) ?? [] {
            for item in menu.items where item.action == #selector(NSText.delete(_:)) && item.keyEquivalent.isEmpty {
                item.keyEquivalent = "\u{8}"
                item.keyEquivalentModifierMask = []
            }
        }
    }
}
