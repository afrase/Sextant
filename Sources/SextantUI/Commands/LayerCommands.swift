import SwiftUI

struct LayerMenu: View {
    var window: LayoutWindowModel?

    var body: some View {
        let session = window?.session
        let current = session?.selection.layer ?? 0
        Button("New Layer") { window?.addLayer() }
            .keyboardShortcut("n", modifiers: [.command, .shift]).disabled(session == nil)
        Button("Duplicate Layer") { session?.duplicateLayer(current) }
            .keyboardShortcut("d", modifiers: [.command, .shift]).disabled(session == nil)
        // Renames in place in the sidebar (spec §9.1); the layer summary's name field works without it.
        Button("Rename Layer…") { window?.startRenaming(layer: current) }.disabled(session == nil || window?.showsSidebar != true)
        Menu("Layer Colour") {
            if let window { LayerColourMenu(model: window, layer: current) }
        }
        .disabled(session == nil)
        Divider()
        Button("Move Layer Up") { window?.moveLayer(by: -1) }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option]).disabled(window?.canShowPreviousLayer != true)
        Button("Move Layer Down") { window?.moveLayer(by: 1) }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option]).disabled(window?.canShowNextLayer != true)
        Divider()
        Button("Copy Layer To…") {}.disabled(true)
        Button("Clear Layer…") { window?.layerPendingClear = current }.disabled(session == nil)
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
                    isOn: Binding(
                        get: { window?.showsFirmwareSettings != true && session.selection.layer == index },
                        set: { _ in
                            window?.showsFirmwareSettings = false
                            session.select(layer: index)
                        })
                )
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
    }
}
