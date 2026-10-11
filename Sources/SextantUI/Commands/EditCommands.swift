import SwiftUI

/// Edit menu additions after the pasteboard group (spec §9.1).
struct EditItems: View {
    var window: LayoutWindowModel?

    var body: some View {
        Divider()
        MakeTransparentItem(window: window)
        Button("Find Key…") { window?.openPalette(.keys) }.keyboardShortcut("f").disabled(window?.session == nil)
        // ⇧⌘O also opens it (the window's hidden alias button; a menu item takes one shortcut).
        Button("Command Palette") { window?.openPalette() }.keyboardShortcut("k").disabled(window?.session == nil)
    }
}

/// Edit ▸ Make Transparent (also in the Key menu, as the spec lists it in both).
struct MakeTransparentItem: View {
    var window: LayoutWindowModel?

    var body: some View {
        // Off while a text field may have focus: ⌘⌫ in it reaches the menu before the field and would edit the key.
        Button("Make Transparent") { window?.session?.makeTransparent() }
            .keyboardShortcut(.delete)
            .disabled(window?.hasSelectedKey != true || window?.isEditingText == true)
    }
}
