import SextantApplication
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
    /// The global layer shortcuts (ADR 0048); `LayerShortcuts` saves it through the composition root.
    static let layerShortcutsOn = "layerShortcutsOn"
}

/// Draws the recorder for one layer's global shortcut. The composition root passes the hot-key library's, so the UI
/// never sees it (ADR 0048).
public typealias LayerShortcutRecorder = @MainActor (_ layer: Int) -> AnyView

/// Settings › Keyboard (spec §8.9): live presses, Follow, the overlay HUD and the global layer shortcuts.
public struct KeyboardSettings: View {
    var layerShortcuts: LayerShortcuts?
    var recorder: LayerShortcutRecorder?
    @AppStorage(SettingsKey.showsKeyPresses) private var showsPresses = true
    @AppStorage(SettingsKey.followsKeyboardOnConnect) private var follows = true
    @AppStorage(SettingsKey.showsOverlay) private var showsOverlay = true
    @AppStorage(SettingsKey.overlayDelay) private var delay = 150
    @AppStorage(SettingsKey.overlayPosition) private var position = OverlayPosition.bottom
    @AppStorage(SettingsKey.overlaySize) private var size = OverlaySize.medium
    @AppStorage(SettingsKey.tintsOverlay) private var tints = false
    @AppStorage(SettingsKey.lockedLayerOverlay) private var locked = LockedLayerOverlay.reminder

    /// Without `recorder`, each layer's shortcut shows as text.
    public init(layerShortcuts: LayerShortcuts? = nil, recorder: LayerShortcutRecorder? = nil) {
        self.layerShortcuts = layerShortcuts
        self.recorder = recorder
    }

    /// Follow turns on when a keyboard connects unless the user turned that off; the composition root hands this to
    /// `LiveSession`, which asks at each connect.
    public static func followsOnConnect() -> Bool {
        UserDefaults.standard.object(forKey: SettingsKey.followsKeyboardOnConnect) as? Bool ?? true
    }

    /// Whether the global layer shortcuts are on; off by default.
    public static func layerShortcutsOn() -> Bool { UserDefaults.standard.bool(forKey: SettingsKey.layerShortcutsOn) }

    public static func saveLayerShortcutsOn(_ on: Bool) { UserDefaults.standard.set(on, forKey: SettingsKey.layerShortcutsOn) }

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
            if let layerShortcuts { LayerShortcutsSection(shortcuts: layerShortcuts, recorder: recorder) }
        }
        .formStyle(.grouped)
    }

    private var overlay: some View {
        Section {
            Toggle("Show overlay while a layer is held", isOn: $showsOverlay)
            Group {
                LabeledContent("Delay") {
                    HStack {
                        // The binding rounds to 10 ms steps: `step: 10` would draw 51 ticks, which run together into a dotted line.
                        Slider(value: Binding(get: { Double(delay) }, set: { delay = Int(($0 / 10).rounded()) * 10 }), in: 0...500) {
                            Text("Delay")
                        } ticks: {
                            SliderTickContentForEach(Array(stride(from: 0.0, through: 500, by: 100)), id: \.self, content: SliderTick.init)
                        }
                        .labelsHidden()
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
                While Live View is on, shows the layer you’re holding over other apps once the delay passes, for a \
                layout in your library. A locked layer can show a small reminder until the keyboard is back on its base \
                layer. Turn on Live View from Sextant in the menu bar or a layout window’s toolbar.
                """
            )
            .foregroundStyle(.secondary)
        }
    }
}

/// The global layer shortcuts (spec §9.4, ADR 0048): the switch, then each layer's shortcut, five to a column.
private struct LayerShortcutsSection: View {
    @Bindable var shortcuts: LayerShortcuts
    var recorder: LayerShortcutRecorder?

    var body: some View {
        Section {
            Toggle("Move the keyboard’s layer from any app", isOn: $shortcuts.isOn)
            if shortcuts.isOn {
                // First, under the switch: a press that moved nothing only beeps, so this is where the user looks.
                if let refusal = shortcuts.refusal {
                    Label(String(localized: "The last shortcut moved nothing. \(refusal.localizedDescription)"), systemImage: "info.circle")
                        .labelStyle(StatusLabelStyle(tint: .secondary))
                }
                HStack(alignment: .top, spacing: 28) {
                    column(0..<5)
                    column(5..<10)
                }
                .frame(maxWidth: .infinity)
                ForEach(shortcuts.conflicts.keys.sorted(), id: \.self) { layer in
                    if let conflict = shortcuts.conflicts[layer] {
                        Label(
                            Self.text(conflict, layer: layer, shortcut: shortcuts.shortcuts[layer]),
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .labelStyle(StatusLabelStyle(tint: Tokens.warning.color))
                    }
                }
            }
        } header: {
            Text("Layer shortcuts")
        } footer: {
            Text(
                """
                Each shortcut (⌃⌥0 to ⌃⌥9 unless you record others) moves the keyboard to its layer while Live View \
                is on, whichever app you’re in; one that can’t beeps, and says why above. While they’re on, other apps \
                don’t get those keys.
                """
            )
            .foregroundStyle(.secondary)
        }
    }

    private func column(_ layers: Range<Int>) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            ForEach(layers, id: \.self) { layer in
                GridRow {
                    Text("Layer \(layer)")
                    if let recorder {
                        recorder(layer)
                    } else {
                        // Drawn like the recorder, for previews and snapshots.
                        Text(verbatim: shortcuts.shortcuts[layer]?.text ?? "")
                            .frame(width: 130, height: 22)
                            .background(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
                    }
                }
            }
        }
    }

    private static func text(_ conflict: HotKeyConflict, layer: Int, shortcut: HotKeyShortcut?) -> String {
        let keys = shortcut?.text ?? ""
        return switch conflict {
        case .inUse: String(localized: "Layer \(layer): another app already uses \(keys). Record a different shortcut.")
        case .takenBySystem:
            String(
                localized:
                    "Layer \(layer): \(keys) is a macOS shortcut. Record a different one, or turn it off in System Settings › Keyboard.")
        }
    }
}
