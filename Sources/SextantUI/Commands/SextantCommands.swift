import SextantApplication
import SwiftUI

/// The menu bar (spec §9.1), routed to the key window's model. Items for later steps are present but disabled.
/// The system Undo / Redo group is left alone: it already names the action and respects text fields.
struct SextantCommands: Commands {
    @FocusedValue(LayoutWindowModel.self) private var window
    /// File ▸ New Layout works with no window open.
    let library: Library
    @AppStorage(BenchGrid.key) private var showsGrid = true

    var body: some Commands {
        SidebarCommands()
        InspectorCommands()
        // New Layout takes ⌘N (spec §9.1); FileNewItems keeps New Window on ⌥⌘N.
        CommandGroup(replacing: .newItem) { FileNewItems(window: window, library: library) }
        // After, not replacing: the system group holds Close (⌘W) and Close All (⌥⌘W).
        CommandGroup(after: .saveItem) { FileSaveItems(window: window) }
        CommandGroup(replacing: .printItem) {
            Button("Print Layout…") {}.keyboardShortcut("p").disabled(true)
        }
        CommandGroup(after: .pasteboard) { EditItems(window: window) }
        CommandGroup(after: .sidebar) {
            ViewMenuItems(window: window, showsGrid: $showsGrid)
        }
        CommandMenu("Layer") { LayerMenu(window: window) }
        CommandMenu("Key") { KeyMenu(window: window) }
        CommandMenu("Keyboard") { KeyboardMenu(window: window) }
        CommandGroup(before: .windowList) {
            Button("Main Window") {}.keyboardShortcut("0").disabled(true)
        }
        CommandGroup(replacing: .help) {
            Button("Sextant Help") {}.disabled(true)
            Button("Keyboard Shortcuts") {}.keyboardShortcut("/").disabled(true)
            Button("Flashing Help") {}.disabled(true)
            Button("Privacy") {}.disabled(true)
        }
    }
}
