import SextantDomain
import SwiftUI

struct KeyMenu: View {
    var window: LayoutWindowModel?

    var body: some View {
        let session = window?.session
        let hasKey = window?.hasSelectedKey == true
        Button("Change Keycode…") {}.disabled(true)
        Button("Record Key") {}.keyboardShortcut("r", modifiers: [.command, .shift]).disabled(true)
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
            .disabled(!hasKey || window?.isEditingKeyLabel == true)
        Button("Override on This Layer") { session?.overrideInherited() }.disabled(window?.canOverrideKey != true)
        Menu("LED Colour") { KeyColourMenu(window: window) }.disabled(!hasKey)
        Divider()
        Button("Select Key by Pressing It") {}.keyboardShortcut("l", modifiers: [.command, .shift]).disabled(true)
        Button("Copy QMK Expression") { session?.copyQMKExpression() }
            .keyboardShortcut("c", modifiers: [.command, .option, .shift]).disabled(!hasKey)
    }
}
