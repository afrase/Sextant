import SextantApplication
import SextantDomain
import SwiftUI

/// Sextant ▸ Check for Updates…, named for the version once a scheduled check finds one (ADR 0070). Sparkle's window
/// answers. A view, so the menu follows the use case: a `Commands` body reading it directly may not.
struct UpdateMenuItem: View {
    var updates: SoftwareUpdates
    var windows: WindowRouter

    var body: some View {
        Button(
            updates.notice.map { String(localized: "Update to Sextant \($0.description)…") }
                ?? String(localized: "Check for Updates…")
        ) {
            // Brings Sextant forward first: from the menu bar, it may have no window and no Dock icon.
            windows.showWindow { updates.check() }
        }
        .disabled(!updates.canCheck)
    }
}

/// Settings › General's Updates section (ADR 0070).
struct UpdatesSection: View {
    @Bindable var updates: SoftwareUpdates

    var body: some View {
        Section {
            if updates.isSupported {
                Toggle("Check for updates automatically", isOn: $updates.checksAutomatically)
                Toggle("Download and install updates automatically", isOn: $updates.installsAutomatically)
                    .disabled(!updates.checksAutomatically)
            }
            LabeledContent {
                if updates.isSupported {
                    Button("Check Now") { updates.check() }.disabled(!updates.canCheck)
                }
            } label: {
                Text(version)
                if let last = updates.lastChecked {
                    // Redrawn each minute, so "3 hours ago" stays true while Settings is open.
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        Text("Last checked \(last.formatted(.relative(presentation: .named, unitsStyle: .wide)))").id(context.date)
                    }
                }
            }
        } header: {
            Text("Updates")
        } footer: {
            Text(footer).foregroundStyle(.secondary)
        }
    }

    private var version: String {
        updates.current.map { String(localized: "This is Sextant \($0.description).") }
            ?? String(localized: "This build doesn’t say its version.")
    }

    private var footer: String {
        guard updates.isSupported else {
            return String(localized: "This build can’t update itself. Release builds from GitHub or Homebrew can.")
        }
        let installs = String(
            localized: "Updates are signed, and Sextant checks the signature before it installs one.")
        guard updates.checksAutomatically else {
            return String(localized: "Sextant asks GitHub for its newest release only when you check. \(installs)")
        }
        let asks = String(
            localized: "Once a day, Sextant asks GitHub for its newest release. GitHub sees your IP address and Sextant’s version.")
        return updates.installsAutomatically
            ? String(localized: "\(asks) A newer release downloads by itself and installs when you quit Sextant. \(installs)")
            : String(localized: "\(asks) Sextant asks before it downloads anything. \(installs)")
    }
}
