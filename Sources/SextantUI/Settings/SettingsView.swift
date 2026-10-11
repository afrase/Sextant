import SextantApplication
import SwiftUI

/// Which toolchain builds firmware (Settings › Build). The composition root reads the choice when it builds.
public enum BuildBackend: String, CaseIterable, Sendable {
    /// Apple's containerization: a pinned Linux VM with ZSA's compiler (ADR 0018, the default).
    case container
    /// A managed QMK toolchain on this Mac (the fallback).
    case native

    /// The user-defaults key.
    public static let key = "buildBackend"

    /// The stored choice.
    public static var current: Self { UserDefaults.standard.string(forKey: key).flatMap(Self.init(rawValue:)) ?? .container }
}

/// Reports a backend's build tools status. It only looks; it never downloads (the setup step does, with consent).
public typealias BuildToolsStatus = @MainActor (BuildBackend) async -> ToolchainStatus

/// App settings (spec §8.9): General, Build and Privacy. Settings nothing reads yet are stored for later steps.
struct SettingsView: View {
    var buildToolsStatus: BuildToolsStatus?

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Build", systemImage: "hammer") { BuildSettings(status: buildToolsStatus) }
            Tab("Privacy", systemImage: "hand.raised") { PrivacySettings() }
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
}

public struct GeneralSettings: View {
    @AppStorage(SettingsKey.keyboardConnectAction) private var connectAction = "nothing"
    @AppStorage(BenchGrid.key) private var showsGrid = true
    @AppStorage(SettingsKey.notifiesWhenFlashFinishes) private var notifies = false

    public init() {}

    public var body: some View {
        Form {
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
    @AppStorage(BuildBackend.key) private var backend = BuildBackend.container
    @AppStorage(SettingsKey.prefersOryxBuild) private var prefersOryxBuild = true
    @State private var toolsStatus: ToolchainStatus?

    /// `known` shows a status before the first check finishes (snapshots run no tasks).
    public init(status: BuildToolsStatus?, known: ToolchainStatus? = nil) {
        self.status = status
        _toolsStatus = State(initialValue: known)
    }

    public var body: some View {
        Form {
            Section {
                Picker("Build tools", selection: $backend) {
                    Text("Apple container (recommended)").tag(BuildBackend.container)
                    Text("Managed toolchain on this Mac").tag(BuildBackend.native)
                }
                .pickerStyle(.radioGroup)
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
            } footer: {
                Text("The container builds in a small Linux VM with ZSA's compiler; the managed toolchain builds on this Mac.")
                    .foregroundStyle(.secondary)
            }
            Toggle("Use Oryx's build when the layout is unchanged since import", isOn: $prefersOryxBuild)
        }
        .formStyle(.grouped)
        .task(id: backend) {
            toolsStatus = nil
            toolsStatus = await status?(backend)
        }
    }
}

/// A status line: the icon tinted, the text wrapping in secondary.
private struct StatusLabelStyle: LabelStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon.foregroundStyle(tint)
            configuration.title.foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

public struct PrivacySettings: View {
    @AppStorage(SettingsKey.recordsHeatmap) private var recordsHeatmap = false
    @AppStorage(SettingsKey.heatmapRetentionDays) private var retentionDays = 90

    public init() {}

    public var body: some View {
        Form {
            Section("Live keyboard") {
                Text(
                    """
                    Sextant reads the active layer and which key positions are down over the keyboard's raw HID interface. \
                    It sees positions, never the characters you type. Key events stay in memory on this Mac and are never \
                    written to disk, and the live display pauses while you type in a password field.
                    """
                )
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                Toggle("Record a heatmap of key presses", isOn: $recordsHeatmap)
                Picker("Keep presses for", selection: $retentionDays) {
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("1 year").tag(365)
                }
                .disabled(!recordsHeatmap)
            } header: {
                Text("Heatmap")
            } footer: {
                Text("Off unless you turn it on. Counts presses per key position on this Mac, to show which keys you use most.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
