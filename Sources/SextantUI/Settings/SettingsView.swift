import SextantApplication
import SwiftUI

/// Reports the build tools' status. It only looks; it never downloads (the setup step does, with consent).
public typealias BuildToolsStatus = @MainActor () async -> ToolchainStatus

/// The firmware commits builds are pinned to; the composition root passes SextantBuild's pins.
public typealias FirmwareSource = (firmware: String, modules: String)

/// App settings (spec §8.9): General, Keyboard, Build, Privacy and Advanced. Settings nothing reads yet are stored for
/// later steps.
struct SettingsView: View {
    var buildToolsStatus: BuildToolsStatus?
    var firmwareSource: FirmwareSource?
    var trace: RawHIDTrace
    var layerShortcuts: LayerShortcuts
    var layerShortcutRecorder: LayerShortcutRecorder?
    var heatmap: HeatmapRecorder

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Keyboard", systemImage: "keyboard") {
                KeyboardSettings(layerShortcuts: layerShortcuts, recorder: layerShortcutRecorder)
            }
            Tab("Build", systemImage: "hammer") { BuildSettings(status: buildToolsStatus, source: firmwareSource) }
            Tab("Privacy", systemImage: "hand.raised") { PrivacySettings(heatmap: heatmap) }
            Tab("Advanced", systemImage: "gearshape.2") { AdvancedSettings(trace: trace) }
        }
        .frame(width: 520)
    }
}

/// Keys for settings that later steps read.
enum SettingsKey {
    static let keyboardConnectAction = "keyboardConnectAction"
    static let notifiesWhenFlashFinishes = "notifiesWhenFlashFinishes"
    static let prefersOryxBuild = "prefersOryxBuild"
    static let recordsHeatmap = "recordsHeatmap"
    static let heatmapRetentionDays = "heatmapRetentionDays"
    /// The Device popover's note about live data, shown at the first connect (spec §12.3).
    static let seenLiveDataNote = "seenLiveDataNote"
}

public struct GeneralSettings: View {
    @AppStorage(SettingsKey.keyboardConnectAction) private var connectAction = "nothing"
    @AppStorage(BenchGrid.key) private var showsGrid = true
    @AppStorage(SettingsKey.notifiesWhenFlashFinishes) private var notifies = false
    @AppStorage(SettingsKey.showsInMenuBar) private var showsInMenuBar = true
    @AppStorage(SettingsKey.showsMenuBarLayerColor) private var showsLayerColor = false
    @AppStorage(SettingsKey.keepsInMenuBar) private var keepsInMenuBar = false

    public init() {}

    public var body: some View {
        Form {
            Section {
                Toggle("Show in menu bar", isOn: $showsInMenuBar)
                Group {
                    Toggle("Show the layer’s color in the menu bar", isOn: $showsLayerColor)
                    Toggle("Keep Sextant in the menu bar when its windows are closed", isOn: $keepsInMenuBar)
                }
                .disabled(!showsInMenuBar)
            } footer: {
                Text("Kept in the menu bar, Sextant leaves the Dock when you close its last window. Open it again from the menu bar.")
                    .foregroundStyle(.secondary)
            }
            Picker("When the keyboard connects", selection: $connectAction) {
                Text("Open Sextant").tag("open")
                Text("Do nothing").tag("nothing")
            }
            Toggle("Show grid behind the keyboard", isOn: $showsGrid)
            Toggle("Notify when a flash finishes", isOn: $notifies)
        }
        .formStyle(.grouped)
    }
}

public struct BuildSettings: View {
    var status: BuildToolsStatus?
    var source: FirmwareSource?
    @AppStorage(SettingsKey.prefersOryxBuild) private var prefersOryxBuild = true
    @State private var toolsStatus: ToolchainStatus?

    /// `known` shows a status before the first check finishes (snapshots run no tasks).
    public init(status: BuildToolsStatus?, source: FirmwareSource?, known: ToolchainStatus? = nil) {
        self.status = status
        self.source = source
        _toolsStatus = State(initialValue: known)
    }

    public var body: some View {
        Form {
            Section {
                switch toolsStatus {
                case let .ready(detail)?: Label(detail, systemImage: "checkmark.circle.fill").labelStyle(StatusLabelStyle(tint: .green))
                case let .needsSetup(detail)?:
                    Label(
                        "\(detail) Sextant sets them up the first time you build, after you agree to the download.",
                        systemImage: "arrow.down.circle"
                    )
                    .labelStyle(StatusLabelStyle(tint: .secondary))
                case nil: Text("Checking the build tools…").foregroundStyle(.secondary)
                }
            } header: {
                Text("Build tools")
            } footer: {
                Text(
                    """
                    Sextant builds on this Mac with the compiler ZSA uses. \
                    Each build runs sandboxed: no network, and no access to your files.
                    """
                )
                .foregroundStyle(.secondary)
            }
            if let source {
                LabeledContent("Firmware source") {
                    Text("ZSA fork \(String(source.firmware.prefix(7))), modules \(String(source.modules.prefix(7)))")
                        .textSelection(.enabled)
                }
            }
            Toggle("Use Oryx's build when the layout is unchanged since import", isOn: $prefersOryxBuild)
        }
        .formStyle(.grouped)
        .task { toolsStatus = await status?() }
    }
}

/// A status line: the icon tinted, the text wrapping in secondary.
struct StatusLabelStyle: LabelStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon.foregroundStyle(tint)
            configuration.title.foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

public struct PrivacySettings: View {
    @Bindable var heatmap: HeatmapRecorder
    @State private var confirmsClear = false

    public init(heatmap: HeatmapRecorder) { self.heatmap = heatmap }

    /// Whether heatmap recording is on; off by default (ADR 0053).
    public static func recordsHeatmap() -> Bool { UserDefaults.standard.bool(forKey: SettingsKey.recordsHeatmap) }

    /// How many days of heatmap counts are kept; 30 by default.
    public static func heatmapRetentionDays() -> Int {
        UserDefaults.standard.object(forKey: SettingsKey.heatmapRetentionDays) as? Int ?? 30
    }

    public static func saveHeatmap(isOn: Bool, retentionDays: Int) {
        UserDefaults.standard.set(isOn, forKey: SettingsKey.recordsHeatmap)
        UserDefaults.standard.set(retentionDays, forKey: SettingsKey.heatmapRetentionDays)
    }

    public var body: some View {
        Form {
            Section("Live keyboard") {
                Text(
                    """
                    Sextant reads the active layer and which key positions are down over the keyboard's raw HID interface. \
                    It sees positions, never the characters you type. Key events stay in memory on this Mac, and the live \
                    display and the heatmap pause while you type in a password field.
                    """
                )
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                Toggle("Record a heatmap of key presses", isOn: $heatmap.isOn)
                Picker("Keep presses for", selection: $heatmap.retentionDays) {
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("1 year").tag(365)
                }
                .disabled(!heatmap.isOn)
                LabeledContent {
                    Button("Clear Heatmap Data…") { confirmsClear = true }
                } label: {
                    Text("Every layout’s counts")
                }
            } header: {
                Text("Heatmap")
            } footer: {
                Text(
                    """
                    Off unless you turn it on. Only hourly counts per key position are saved, on this Mac and outside \
                    your layouts, so exports never include them.
                    """
                )
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .alert(Text("Clear all heatmap data?"), isPresented: $confirmsClear) {
            Button("Clear", role: .destructive) { Task { await heatmap.clear(nil) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes every key press Sextant has counted, for every layout. It can’t be undone.")
        }
    }
}
