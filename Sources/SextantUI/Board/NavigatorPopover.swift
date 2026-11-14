import SextantApplication
import SextantDomain
import SwiftUI

/// What clicking the board's Navigator disc shows (ADR 0069): the settings people reach for most, in two halves that
/// behave differently. "On this Mac" is Sextant's trackpad driver, which applies to every layout at once; "On the
/// keyboard" is this layout's firmware, which changes only after Build & Flash. Each half links to its full page.
public struct NavigatorPopover: View {
    var navigator: NavigatorConfig
    /// Nil where there's no driver.
    var driver: TrackpadDriver?
    var showMacSettings: () -> Void
    var showFirmwareSettings: () -> Void

    public init(
        navigator: NavigatorConfig, driver: TrackpadDriver?, showMacSettings: @escaping () -> Void,
        showFirmwareSettings: @escaping () -> Void
    ) {
        self.navigator = navigator
        self.driver = driver
        self.showMacSettings = showMacSettings
        self.showFirmwareSettings = showFirmwareSettings
    }

    public var body: some View {
        Form {
            if navigator.kind == .trackpad, let driver {
                Section("On this Mac") {
                    Toggle(
                        "Use Sextant for the trackpad",
                        isOn: Binding(get: { driver.settings.isEnabled }, set: { on in Task { await driver.setEnabled(on) } }))
                    status(driver)
                    if driver.settings.isEnabled { quickSettings(driver) }
                    Button("More in Settings…", action: showMacSettings)
                }
            }
            Section {
                LabeledContent("Navigator") {
                    Text(verbatim: "\(FirmwareSettings.title(navigator.kind)) · \(FirmwareSettings.title(navigator.side))")
                }
                Button("Firmware Settings…", action: showFirmwareSettings)
            } header: {
                Text("On the keyboard")
            } footer: {
                Text("Kind, side and auto-mouse are part of this layout’s firmware. Changes apply after Build & Flash.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .task { await driver?.refresh() }
    }

    @ViewBuilder private func status(_ driver: TrackpadDriver) -> some View {
        switch driver.status {
        case .off:
            EmptyView()
        case .needsInputMonitoring, .needsAccessibility:
            LabeledContent {
                Button("Allow in Settings…", action: showMacSettings)
            } label: {
                Label("Sextant needs your permission first", systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
            }
        case .waitingForTrackpad:
            Label("Waiting for a Navigator trackpad", systemImage: "cable.connector").foregroundStyle(.secondary)
        case .running:
            Label("Driving the Navigator trackpad", systemImage: "checkmark.circle").foregroundStyle(.secondary)
        case let .failed(error):
            Label(error.localizedDescription, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func quickSettings(_ driver: TrackpadDriver) -> some View {
        if let speed = driver.settings.pointer.trackingSpeed {
            ValueSlider(
                title: "Tracking speed", value: speed, range: TrackpadSettings.Pointer.trackingSpeedRange, step: 0.0625,
                low: "Slow", high: "Fast", digits: 2
            ) { value in driver.update { $0.pointer.trackingSpeed = value } }
        }
        ValueSlider(
            title: "Pad rotation", value: driver.settings.rotation, range: TrackpadSettings.rotationRange, step: 1,
            low: "−180°", high: "180°", digits: 0, unit: "°"
        ) { value in driver.update { $0.rotation = value } }
        Toggle(
            "Tap to click",
            isOn: Binding(get: { driver.settings.tapping.tapToClick }, set: { on in driver.update { $0.tapping.tapToClick = on } }))
        Toggle(
            "Tap, then touch and move to drag",
            isOn: Binding(
                get: { driver.settings.dragging.tapThenDrag }, set: { on in driver.update { $0.dragging.tapThenDrag = on } }))
    }
}

extension LayoutWindowModel {
    /// The Firmware Settings page at its Navigator section, with any filter that would hide it cleared.
    func showNavigatorFirmwareSettings() {
        destination = .firmwareSettings
        firmwareSettings.clearFilters()
        firmwareSettings.scrollTarget = FirmwareSettings.navigator
    }
}
