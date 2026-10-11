import SwiftUI

/// Edit menu additions after the pasteboard group (spec §9.1).
struct EditItems: View {
    var window: LayoutWindowModel?

    var body: some View {
        Divider()
        MakeTransparentItem(window: window)
        Button("Find Key…") {}.keyboardShortcut("f").disabled(true)
        Button("Command Palette") {}.keyboardShortcut("k").disabled(true)
    }
}

/// Edit ▸ Make Transparent (also in the Key menu, as the spec lists it in both).
struct MakeTransparentItem: View {
    var window: LayoutWindowModel?

    var body: some View {
        Button("Make Transparent") { window?.session?.makeTransparent() }
            .keyboardShortcut(.delete).disabled(window?.hasSelectedKey != true || window?.isEditingKeyLabel == true)
    }
}
