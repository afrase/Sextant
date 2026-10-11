import SextantApplication
import SextantDomain
import SwiftUI

/// The Firmware Settings inspector (spec §8.8): sections with changed counts (a click scrolls the page), the Changed
/// list with each default struck through, and Reset All.
struct FirmwareSettingsInspector: View {
    var model: LayoutWindowModel
    var session: EditSession
    @State private var confirmsReset = false

    var body: some View {
        let changed = session.layout.changedSettings()
        let changedIDs = Set(changed.map(\.id))
        Text("Sections").font(.headline)
        ForEach(FirmwareSettings.sections(for: session.layout)) { section in
            let count = section.settings.count { changedIDs.contains($0.id) }
            Button {
                model.settingsScrollTarget = section.id
            } label: {
                HStack {
                    Text(section.title)
                    Spacer()
                    if count > 0 { Text(verbatim: "\(count)").monospacedDigit().foregroundStyle(.tint) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(count == 0 ? "" : String(localized: "\(count) changed"))
        }
        Divider()
        Text("Changed (\(changed.count))").font(.headline)
        if changed.isEmpty {
            Text("Every setting has its default value.").font(.callout).foregroundStyle(.secondary)
        }
        ForEach(changed) { setting in
            let value = session.layout.storedValue(of: setting)
            VStack(alignment: .leading, spacing: 2) {
                Text(setting.title)
                HStack(spacing: 6) {
                    Text(setting.format(setting.unsetValue)).strikethrough().foregroundStyle(.secondary)
                    Text(verbatim: "→").foregroundStyle(.secondary).accessibilityHidden(true)
                    Text(setting.format(value))
                }
                .font(.callout)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                String(localized: "\(setting.title): \(setting.format(value)), default \(setting.format(setting.unsetValue))"))
        }
        Button("Reset All to Defaults…") { confirmsReset = true }
            .disabled(changed.isEmpty)
            .confirmationDialog("Reset every firmware setting to its default?", isPresented: $confirmsReset) {
                Button("Reset All", role: .destructive) {
                    // One event, so the undo manager groups the resets into one step.
                    for setting in changed { session.setSetting(setting.id, to: nil) }
                }
            } message: {
                Text("You can undo this.")
            }
        Text("Settings take effect after you build and flash. Values equal to the default aren't stored.")
            .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
