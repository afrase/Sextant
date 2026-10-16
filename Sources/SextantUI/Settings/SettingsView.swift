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
    /// Keyboard's overlay Preview shows on it.
    var overlayHUD: OverlayHUD

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Keyboard", systemImage: "keyboard") {
                KeyboardSettings(layerShortcuts: layerShortcuts, recorder: layerShortcutRecorder, overlay: overlayHUD)
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
    /// A shorter retention, asked about first: it deletes the older counts at once.
    @State private var shorterRetention: Int?

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

    static let retentions = [
        (days: 30, title: String(localized: "30 days")), (days: 90, title: String(localized: "90 days")),
        (days: 365, title: String(localized: "1 year")),
    ]

    /// "45 days" (or "1 day") for a saved retention the picker doesn't offer.
    private static var dayCount: DateComponentsFormatter {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = .day
        formatter.unitsStyle = .full
        return formatter
    }

    static func title(_ days: Int?) -> String {
        retentions.first { $0.days == days }?.title ?? days.flatMap { dayCount.string(from: DateComponents(day: $0)) } ?? ""
    }

    /// Keeping counts longer applies at once; keeping them for less asks first.
    private var retention: Binding<Int> {
        Binding(
            get: { heatmap.retentionDays },
            set: { days in
                if days < heatmap.retentionDays { shorterRetention = days } else { heatmap.retentionDays = days }
            })
    }

    /// A save or read of the heatmap that failed, while that lasts.
    @ViewBuilder private var failure: some View {
        if let error = heatmap.lastError?.errorDescription {
            Label {
                Text(error).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Tokens.danger.color)
            }
        }
    }

    private var heatmapNote: some View {
        Text(
            """
            Off unless you turn it on. Presses are counted only while Live View is on. Sextant saves counts of presses \
            per key position and of layer changes, by the hour, never the keys’ order or exact times. They’re kept on this \
            Mac, apart from your layouts, so they never go with a layout you export or share.
            """
        )
        .foregroundStyle(.secondary)
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
                Picker("Keep presses for", selection: retention) {
                    ForEach(Self.retentions, id: \.days) { Text($0.title).tag($0.days) }
                }
                .disabled(!heatmap.isOn)
                LabeledContent {
                    Button("Clear Heatmap Data…") { confirmsClear = true }
                } label: {
                    Text("Every layout’s counts")
                }
                failure
            } header: {
                Text("Heatmap")
            } footer: {
                heatmapNote
            }
        }
        .formStyle(.grouped)
        .alert(
            Text("Keep presses for \(Self.title(shorterRetention))?"),
            isPresented: Binding(get: { shorterRetention != nil }, set: { if !$0 { shorterRetention = nil } }),
            presenting: shorterRetention
        ) { days in
            Button("Delete Older Counts", role: .destructive) { heatmap.retentionDays = days }
            Button("Cancel", role: .cancel) {}
        } message: { days in
            Text("Counts older than \(Self.title(days)) are deleted now, for every layout. This can’t be undone.")
        }
        .alert(Text("Clear all heatmap data?"), isPresented: $confirmsClear) {
            Button("Clear", role: .destructive) { Task { await heatmap.clear(nil) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes every key press Sextant has counted, for every layout. It can’t be undone.")
        }
    }
}
