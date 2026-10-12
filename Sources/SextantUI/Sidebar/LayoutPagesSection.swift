import SextantApplication
import SwiftUI

/// The layout's document pages (spec §3.6 "Layout"). Combos, Macros, App Layers and History join in v1.
struct LayoutPagesSection: View {
    var session: EditSession
    /// The page the window shows, so a selected row can keep its badge legible.
    var page: Destination?

    var body: some View {
        Section("Layout") {
            HistoryRow(revisions: session.revisions.count, isSelected: page == .history).tag(Destination.history)
            let changed = session.layout.changedSettings().count
            Label("Firmware Settings", systemImage: "slider.horizontal.3")
                .badge(changed == 0 ? nil : Text(verbatim: "\(changed)").foregroundStyle(.tint))
                .tag(Destination.firmwareSettings)
                .accessibilityValue(changed == 0 ? "" : String(localized: "\(changed) changed from defaults"))
        }
    }
}
