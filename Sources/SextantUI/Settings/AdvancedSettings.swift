import SextantApplication
import SwiftUI

extension SettingsKey {
    /// Notes shown once and then dismissed. Settings › Advanced › Reset all warnings shows them again; a new one-time
    /// note adds its key here.
    static let oneTimeNotes = [seenLiveDataNote]

    static func hasDismissedNotes(in defaults: UserDefaults = .standard) -> Bool {
        oneTimeNotes.contains { defaults.object(forKey: $0) != nil }
    }

    static func resetOneTimeNotes(in defaults: UserDefaults = .standard) { oneTimeNotes.forEach(defaults.removeObject) }
}

/// Settings › Advanced (spec §8.9): the Developer raw-HID log and Reset all warnings.
public struct AdvancedSettings: View {
    @Bindable var trace: RawHIDTrace
    @State private var hasDismissedNotes = SettingsKey.hasDismissedNotes()

    public init(trace: RawHIDTrace) { self.trace = trace }

    public var body: some View {
        Form {
            Section {
                Toggle("Developer raw-HID log (positions only)", isOn: $trace.isOn)
            } footer: {
                Text(
                    """
                    Keeps the last \(RawHIDTrace.capacity) reports Sextant and the keyboard exchange, for the Device \
                    popover. They stay in memory and are never saved; turning the log off clears it. It starts off each \
                    time Sextant opens.
                    """
                )
                .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent {
                    Button("Reset") {
                        SettingsKey.resetOneTimeNotes()
                        hasDismissedNotes = false
                    }
                    .disabled(!hasDismissedNotes)
                } label: {
                    Text("Reset all warnings")
                    Text("Shows notes you dismissed again, such as the one about live data.")
                }
            }
        }
        .formStyle(.grouped)
        // The Device popover dismisses notes in another window.
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            hasDismissedNotes = SettingsKey.hasDismissedNotes()
        }
    }
}
