import SwiftUI

/// Where the overlay HUD sits on the screen with the pointer (spec §8.4).
enum OverlayPosition: String, CaseIterable {
    case bottom, top
}

/// The overlay HUD's size (spec §8.4).
enum OverlaySize: String, CaseIterable {
    case small, medium, large
}

/// What the overlay shows for a locked layer (TG, TO): the full overlay, a reminder pill until the base layer, or
/// nothing (spec §8.4).
enum LockedLayerOverlay: String, CaseIterable {
    case full, reminder, nothing
}

extension SettingsKey {
    static let showsKeyPresses = "showsKeyPresses"
    static let followsKeyboardOnConnect = "followsKeyboardOnConnect"
    // The overlay HUD reads these, with the defaults the pane declares (ADR 0045).
    static let showsOverlay = "showsOverlay"
    static let overlayDelay = "overlayDelayMilliseconds"
    static let overlayPosition = "overlayPosition"
    static let overlaySize = "overlaySize"
    static let tintsOverlay = "tintsOverlay"
    static let lockedLayerOverlay = "lockedLayerOverlay"
}

/// Settings › Keyboard (spec §8.9): live presses, Follow, and the overlay HUD.
public struct KeyboardSettings: View {
    @AppStorage(SettingsKey.showsKeyPresses) private var showsPresses = true
    @AppStorage(SettingsKey.followsKeyboardOnConnect) private var follows = true
    @AppStorage(SettingsKey.showsOverlay) private var showsOverlay = true
    @AppStorage(SettingsKey.overlayDelay) private var delay = 150
    @AppStorage(SettingsKey.overlayPosition) private var position = OverlayPosition.bottom
    @AppStorage(SettingsKey.overlaySize) private var size = OverlaySize.medium
    @AppStorage(SettingsKey.tintsOverlay) private var tints = false
    @AppStorage(SettingsKey.lockedLayerOverlay) private var locked = LockedLayerOverlay.reminder

    public init() {}

    /// Follow turns on when a keyboard connects unless the user turned that off; the composition root hands this to
    /// `LiveSession`, which asks at each connect.
    public static func followsOnConnect() -> Bool {
        UserDefaults.standard.object(forKey: SettingsKey.followsKeyboardOnConnect) as? Bool ?? true
    }

    public var body: some View {
        Form {
            Section {
                Toggle("Show key presses on the board", isOn: $showsPresses)
                Toggle("Follow the keyboard by default", isOn: $follows)
            } header: {
                Text("Live keyboard")
            } footer: {
                Text("Follow shows the keyboard’s layer as it changes. Choosing a layer by hand stops it, and ⌘L resumes it.")
                    .foregroundStyle(.secondary)
            }
            overlay
        }
        .formStyle(.grouped)
    }

    private var overlay: some View {
        Section {
            Toggle("Show overlay while a layer is held", isOn: $showsOverlay)
            Group {
                LabeledContent("Delay") {
                    HStack {
                        Slider(value: Binding(get: { Double(delay) }, set: { delay = Int($0) }), in: 0...500, step: 10)
                            .labelsHidden()
                            .accessibilityLabel(String(localized: "Delay"))
                            .accessibilityValue(String(localized: "\(delay) ms"))
                        Text("\(delay) ms").monospacedDigit().foregroundStyle(.secondary).frame(width: 52, alignment: .trailing)
                    }
                }
                Picker("Position", selection: $position) {
                    Text("Bottom center").tag(OverlayPosition.bottom)
                    Text("Top center").tag(OverlayPosition.top)
                }
                Picker("Size", selection: $size) {
                    Text("Small").tag(OverlaySize.small)
                    Text("Medium").tag(OverlaySize.medium)
                    Text("Large").tag(OverlaySize.large)
                }
                .pickerStyle(.segmented)
                Toggle("Tint with the layer color", isOn: $tints)
                Picker("When a layer is locked", selection: $locked) {
                    Text("Full overlay").tag(LockedLayerOverlay.full)
                    Text("Reminder").tag(LockedLayerOverlay.reminder)
                    Text("Nothing").tag(LockedLayerOverlay.nothing)
                }
            }
            .disabled(!showsOverlay)
        } header: {
            Text("Overlay")
        } footer: {
            Text(
                """
                Shows the layer you hold above other apps once the delay passes. A locked layer can show a small \
                reminder until the keyboard is back on its base layer.
                """
            )
            .foregroundStyle(.secondary)
        }
    }
}
