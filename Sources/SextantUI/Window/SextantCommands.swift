import SextantApplication
import SextantDomain
import SwiftUI

/// The menu bar (spec §9.1), routed to the key window's model. Items for later steps are present but disabled.
/// The system Undo / Redo group is left alone: it already names the action and respects text fields.
struct SextantCommands: Commands {
    @FocusedValue(LayoutWindowModel.self) private var window
    @AppStorage(BenchGrid.key) private var showsGrid = true

    var body: some Commands {
        SidebarCommands()
        InspectorCommands()
        // ⌘N stays New Window until New Layout exists (spec step 12), so a second layout window can still be opened.
        CommandGroup(after: .newItem) {
            Button("New Layout") {}.disabled(true)
            Button("Import from Oryx…") {}.keyboardShortcut("i", modifiers: [.command, .shift]).disabled(true)
            Button("Import from Connected Keyboard") {}.disabled(true)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save Revision…") {}.keyboardShortcut("s").disabled(true)
            Button("Duplicate Layout") {}.disabled(true)
            Button("Rename Layout…") {}.disabled(true)
            Menu("Export") {
                Button("Layout JSON…") {}
                Button("QMK Source (.zip)…") {}
                Button("Firmware (.bin)…") {}
            }
            .disabled(true)
            ShowInFinderItem(window: window)
        }
        CommandGroup(replacing: .printItem) {
            Button("Print Layout…") {}.keyboardShortcut("p").disabled(true)
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            MakeTransparentItem(window: window)
            Button("Find Key…") {}.keyboardShortcut("f").disabled(true)
            Button("Command Palette") {}.keyboardShortcut("k").disabled(true)
        }
        CommandGroup(after: .sidebar) {
            ViewMenuItems(window: window, showsGrid: $showsGrid)
        }
        CommandMenu("Layer") { LayerMenu(window: window) }
        CommandMenu("Key") { KeyMenu(window: window) }
        CommandMenu("Keyboard") { KeyboardMenu(window: window) }
        CommandGroup(replacing: .help) {
            Button("Sextant Help") {}.disabled(true)
            Button("Keyboard Shortcuts") {}.keyboardShortcut("/").disabled(true)
            Button("Flashing Help") {}.disabled(true)
            Button("Privacy") {}.disabled(true)
        }
    }
}

private struct ShowInFinderItem: View {
    var window: LayoutWindowModel?

    var body: some View {
        Button("Show in Finder") { Task { await window?.showInFinder() } }.disabled(window?.session == nil)
    }
}

/// Edit ▸ Make Transparent (also in the Key menu, as the spec lists it in both).
private struct MakeTransparentItem: View {
    var window: LayoutWindowModel?

    var body: some View {
        Button("Make Transparent") { window?.session?.makeTransparent() }
            .keyboardShortcut(.delete).disabled(window?.hasSelectedKey != true)
    }
}

/// View ▸ Lens, Legends and the bench grid.
private struct ViewMenuItems: View {
    var window: LayoutWindowModel?
    @Binding var showsGrid: Bool

    var body: some View {
        Divider()
        Menu("Lens") {
            ForEach(Array(Lens.allCases.enumerated()), id: \.element) { n, lens in
                Toggle(lens.title, isOn: Binding(get: { window?.lens == lens }, set: { _ in window?.lens = lens }))
                    .keyboardShortcut(KeyEquivalent(Character("\(n + 1)")), modifiers: [.command, .control])
            }
        }
        .disabled(window?.session == nil)
        Menu("Legends") {
            legend(.symbols, nil)
            legend(.qmk, "c")
            legend(.index, "n")
        }
        .disabled(window?.session == nil)
        Toggle("Show Grid Behind Keyboard", isOn: $showsGrid)
        Divider()
    }

    @ViewBuilder private func legend(_ mode: LegendMode, _ key: Character?) -> some View {
        let toggle = Toggle(mode.title, isOn: Binding(get: { window?.legendMode == mode }, set: { _ in window?.legendMode = mode }))
        // Symbols has no shortcut: ⌥⌘1 belongs to the slots (spec §4.9).
        if let key { toggle.keyboardShortcut(KeyEquivalent(key), modifiers: [.command, .option]) } else { toggle }
    }
}

private struct LayerMenu: View {
    var window: LayoutWindowModel?

    var body: some View {
        let session = window?.session
        Button("New Layer") { session?.addLayer() }
            .keyboardShortcut("n", modifiers: [.command, .shift]).disabled(session == nil)
        Button("Duplicate Layer") { if let session { session.duplicateLayer(session.selection.layer) } }
            .keyboardShortcut("d", modifiers: [.command, .shift]).disabled(session == nil)
        Button("Rename Layer…") {}.disabled(true)
        Menu("Layer Colour") {}.disabled(true)
        Divider()
        Button("Move Layer Up") { window?.moveLayer(by: -1) }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option]).disabled(window?.canShowPreviousLayer != true)
        Button("Move Layer Down") { window?.moveLayer(by: 1) }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option]).disabled(window?.canShowNextLayer != true)
        Divider()
        Button("Copy Layer To…") {}.disabled(true)
        Button("Clear Layer…") {}.disabled(true)
        Button("Delete Layer…") { window?.requestDeleteLayer() }.disabled(window?.canDeleteLayer != true)
        Divider()
        Button("Show Previous Layer") { window?.showAdjacentLayer(-1) }
            .keyboardShortcut("[", modifiers: [.command, .shift]).disabled(window?.canShowPreviousLayer != true)
        Button("Show Next Layer") { window?.showAdjacentLayer(1) }
            .keyboardShortcut("]", modifiers: [.command, .shift]).disabled(window?.canShowNextLayer != true)
        if let session {
            Divider()
            // ⌘1–⌘9 show layers 0–8 (spec §6.1).
            ForEach(Array(session.layout.layers.prefix(9).enumerated()), id: \.element.id) { index, layer in
                Toggle(
                    String(localized: "Layer \(index) · \(layer.title)"),
                    isOn: Binding(get: { session.selection.layer == index }, set: { _ in session.select(layer: index) })
                )
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
    }
}

private struct KeyMenu: View {
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
        Button("Disable Key") { session?.disable() }.keyboardShortcut(.delete, modifiers: [.command, .shift]).disabled(!hasKey)
        Button("Override on This Layer") { session?.overrideInherited() }.disabled(window?.canOverrideKey != true)
        Menu("LED Colour") {}.disabled(true)
        Divider()
        Button("Select Key by Pressing It") {}.keyboardShortcut("l", modifiers: [.command, .shift]).disabled(true)
        Button("Copy QMK Expression") { session?.copyQMKExpression() }
            .keyboardShortcut("c", modifiers: [.command, .option, .shift]).disabled(!hasKey)
    }
}

private struct KeyboardMenu: View {
    var window: LayoutWindowModel?

    var body: some View {
        Button("Build") { window?.build(.build) }.keyboardShortcut("b").disabled(window?.canBuild != true)
        Button("Build & Flash") { window?.build(.buildAndFlash) }.keyboardShortcut("r").disabled(window?.canBuild != true)
        Button("Stop") { window?.build(.stop) }.keyboardShortcut(".").disabled(window?.canStop != true)
        Button("Show Build Log") { window?.build(.showLog) }
            .keyboardShortcut("b", modifiers: [.command, .shift]).disabled(window?.onBuild == nil || window?.session == nil)
        Divider()
        Button("Next Issue") {}.keyboardShortcut("'").disabled(true)
        Button("Previous Issue") {}.keyboardShortcut("'", modifiers: [.command, .shift]).disabled(true)
        Divider()
        Toggle("Follow Keyboard", isOn: Binding(get: { window?.isFollowing == true }, set: { window?.isFollowing = $0 }))
            .keyboardShortcut("l").disabled(window?.canFollow != true)
        Menu("Move Keyboard to Layer") {}.disabled(true)
        Button("Preview Lighting on Keyboard") {}.disabled(true)
        Button("Show Overlay While Holding a Layer") {}.disabled(true)
        Divider()
        Button("Device Info…") {}.disabled(true)
        Button("Flash Oryx’s Build of This Revision…") {}.disabled(true)
    }
}
