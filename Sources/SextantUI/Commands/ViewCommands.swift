import SextantDomain
import SwiftUI

/// View ▸ Lens, Legends, History's comparison and the bench grid.
struct ViewMenuItems: View {
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
        Menu("Compare Revision With") { if let history = window?.history { CompareItems(history: history) } }
            .disabled(window?.shownRevision == nil)
        Toggle("Show Grid Behind Keyboard", isOn: $showsGrid)
        Divider()
    }

    @ViewBuilder private func legend(_ mode: LegendMode, _ key: Character?) -> some View {
        let toggle = Toggle(mode.title, isOn: Binding(get: { window?.legendMode == mode }, set: { _ in window?.legendMode = mode }))
        // Symbols has no shortcut: ⌥⌘1 belongs to the slots (spec §4.9).
        if let key { toggle.keyboardShortcut(KeyEquivalent(key), modifiers: [.command, .option]) } else { toggle }
    }
}
