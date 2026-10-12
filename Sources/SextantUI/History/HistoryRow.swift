import SwiftUI

/// The sidebar's History row (spec §3.6) with its revision count.
struct HistoryRow: View {
    var revisions: Int
    var isSelected: Bool

    var body: some View {
        // The selected row's fill is dark grey in dark mode; a secondary badge vanishes on it (as in LayersSection).
        Label("History", systemImage: "clock.arrow.circlepath")
            .badge(revisions == 0 ? nil : Text(verbatim: "\(revisions)").foregroundStyle(isSelected ? .primary : .secondary))
            .accessibilityValue(revisions == 1 ? String(localized: "1 revision") : String(localized: "\(revisions) revisions"))
    }
}
