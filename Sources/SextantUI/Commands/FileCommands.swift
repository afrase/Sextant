import SwiftUI

/// File ▸ New and Import (spec §9.1).
struct FileNewItems: View {
    var body: some View {
        Button("New Layout") {}.disabled(true)
        Button("Import from Oryx…") {}.keyboardShortcut("i", modifiers: [.command, .shift]).disabled(true)
        Button("Import from Connected Keyboard") {}.disabled(true)
    }
}

/// File ▸ Save Revision through Show in Finder (spec §9.1).
struct FileSaveItems: View {
    var window: LayoutWindowModel?

    var body: some View {
        Button("Save Revision…") {}.keyboardShortcut("s").disabled(true)
        Button("Duplicate Layout") {}.disabled(true)
        Button("Rename Layout…") {}.disabled(true)
        Menu("Export") {
            Button("Layout JSON…") {}
            Button("QMK Source (.zip)…") {}
            Button("Firmware (.bin)…") {}
        }
        .disabled(true)
        Button("Show in Finder") { Task { await window?.showInFinder() } }.disabled(window?.session == nil)
    }
}
