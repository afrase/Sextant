import SextantApplication
import SextantDomain
import SwiftUI

/// File ▸ New and Import (spec §9.1). New Layout takes ⌘N; New Window has no shortcut (⌥⌘N is Legends ▸ Key Numbers).
struct FileNewItems: View {
    var window: LayoutWindowModel?
    var library: Library
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("New Layout") { Task { await addBlankLayout(to: library, from: window, openWindow: openWindow) } }
            .keyboardShortcut("n")
        Button("New Window") { openWindow(id: "layout") }
        Divider()
        Button("Import from Oryx…") { window?.openImport() }
            .keyboardShortcut("i", modifiers: [.command, .shift]).disabled(window?.canImport != true)
        Button("Import from Connected Keyboard") { window?.openImport(window?.connectedOryxSerial) }
            .disabled(window?.canImport != true || window?.connectedOryxSerial == nil)
    }
}

/// File ▸ Save Revision through Show in Finder (spec §9.1).
struct FileSaveItems: View {
    var window: LayoutWindowModel?

    var body: some View {
        let id = window?.session?.id
        Button("Save Revision…") { Task { await window?.beginSaveRevision() } }
            .keyboardShortcut("s").disabled(window?.canSaveRevision != true)
        Button("Duplicate Layout") { if let id { Task { await window?.library.duplicate(id) } } }.disabled(id == nil)
        Button("Rename Layout…") { window?.layoutPendingRename = id }.disabled(id == nil)
        Button("Move Layout to Trash…") { window?.layoutPendingTrash = id }.disabled(id.map { window?.canTrash($0) != true } ?? true)
        Menu("Export") {
            Button("Layout JSON…") {}
            Button("QMK Source (.zip)…") {}
            Button("Firmware (.bin)…") {}
        }
        .disabled(true)
        Button("Show in Finder") { Task { await window?.showInFinder() } }.disabled(id == nil)
    }
}

/// File ▸ New Layout and the Welcome card: adds a blank QWERTY layout and shows it, in the asking window when it has no
/// layout open (the Welcome, or one that couldn't open its layout), otherwise in a window of its own.
@MainActor
func addBlankLayout(to library: Library, from window: LayoutWindowModel?, openWindow: OpenWindowAction) async {
    guard let entry = await library.create(.blankQWERTY(title: String(localized: "Untitled Layout"))) else { return }
    if let window, window.session == nil { await window.open(entry.id) } else { openWindow(id: "layout", value: entry.id) }
}
