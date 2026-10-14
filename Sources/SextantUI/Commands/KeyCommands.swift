import SextantDomain
import SwiftUI

struct KeyMenu: View {
    var window: LayoutWindowModel?

    var body: some View {
        let session = window?.session
        let hasKey = window?.hasSelectedKey == true
        Button("Change Keycode…") { window?.openKeycodePicker() }.disabled(!hasKey)
        Button("Record Key") { window?.startRecording() }.keyboardShortcut("r", modifiers: [.command, .shift]).disabled(!hasKey)
        Menu("Edit Slot") {
            ForEach(Array(KeySlot.allCases.enumerated()), id: \.element) { n, slot in
                Toggle(
                    slot.title,
                    isOn: Binding(
                        get: { session?.selection.slot == slot },
                        set: { _ in session?.select(key: session?.selection.keyIndex, slot: slot) })
                )
                .keyboardShortcut(KeyEquivalent(Character("\(n + 1)")), modifiers: [.command, .option])
            }
        }
        .disabled(!hasKey)
        Divider()
        MakeTransparentItem(window: window)
        Button("Disable Key") { session?.disable() }.keyboardShortcut(.delete, modifiers: [.command, .shift])
            .disabled(!hasKey || window?.isEditingText == true)
        Button("Override on This Layer") { session?.overrideInherited() }.disabled(window?.canOverrideKey != true)
        Menu("LED Color") { KeyColourMenu(window: window) }.disabled(!hasKey)
        Divider()
        // Disabled with the reason as its help tag: Live View off, the board hidden, a pick under way (ADR 0052).
        let selectByPressRefusal = window.map { $0.selectByPressRefusal } ?? String(localized: "Open a layout first.")
        Button("Select Key by Pressing It") { window?.startSelectByPress() }.keyboardShortcut("l", modifiers: [.command, .shift])
            .disabled(selectByPressRefusal != nil).help(selectByPressRefusal ?? "")
        Button("Copy QMK Expression") { session?.copyQMKExpression() }
            .keyboardShortcut("c", modifiers: [.command, .option, .shift]).disabled(!hasKey)
    }
}
