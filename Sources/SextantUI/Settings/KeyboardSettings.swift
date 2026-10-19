import SextantApplication
import SwiftUI

/// Where the overlay HUD sits on the screen (spec §8.4, ADR 0062): nine spots, row by row from the top left. `top` and
/// `bottom` are the top and bottom centre, stored under the raw values they had when they were the only two, so a saved
/// setting carries over.
enum OverlayPosition: String, CaseIterable {
    case topLeft, top, topRight
    case middleLeft, center, middleRight
    case bottomLeft, bottom, bottomRight

    /// "Top Left", "Top Center", …, "Center", …
    var title: String {
        switch self {
        case .topLeft: String(localized: "Top Left")
        case .top: String(localized: "Top Center")
        case .topRight: String(localized: "Top Right")
        case .middleLeft: String(localized: "Middle Left")
        case .center: String(localized: "Center")
        case .middleRight: String(localized: "Middle Right")
        case .bottomLeft: String(localized: "Bottom Left")
        case .bottom: String(localized: "Bottom Center")
        case .bottomRight: String(localized: "Bottom Right")
        }
    }

    /// The spot's row: 0 at the top, 1 in the middle, 2 at the bottom.
    var row: Int {
        switch self {
        case .topLeft, .top, .topRight: 0
        case .middleLeft, .center, .middleRight: 1
        case .bottomLeft, .bottom, .bottomRight: 2
        }
    }

    /// The spot's column: 0 on the left, 1 in the centre, 2 on the right.
    var column: Int {
        switch self {
        case .topLeft, .middleLeft, .bottomLeft: 0
        case .top, .center, .bottom: 1
        case .topRight, .middleRight, .bottomRight: 2
        }
    }

    /// The spot at `row` and `column`; nil off the 3×3 grid.
    static func at(row: Int, column: Int) -> Self? {
        allCases.first { $0.row == row && $0.column == column }
    }
}

/// Which display the overlay HUD shows on (ADR 0062).
enum OverlayDisplay: String, CaseIterable {
    /// The one with the pointer when the HUD appears.
    case pointer
    /// The main display: the one with the menu bar.
    case main
}

/// The overlay HUD's size (spec §8.4).
enum OverlaySize: String, CaseIterable {
    case small, medium, large
}

/// What typing on a layer does to its full overlay (ADRs 0064, 0065): nothing, hide it until typing pauses for the
/// delay, or hide it until the layer is held again.
enum OverlayTyping: String, CaseIterable {
    case keepShowing, hideUntilPause, hideUntilNextHold
}

/// What the overlay shows for a locked layer (TG, TO): the full overlay, a reminder pill until the base layer, or
/// nothing (spec §8.4).
enum LockedLayerOverlay: String, CaseIterable {
    case full, reminder, nothing
}

extension SettingsKey {
    static let showsKeyPresses = "showsKeyPresses"
    static let followsKeyboardOnConnect = "followsKeyboardOnConnect"
    // The overlay HUD reads these, with the defaults the pane declares (ADRs 0045, 0062).
    static let showsOverlay = "showsOverlay"
    static let overlayDelay = "overlayDelayMilliseconds"
    static let overlayPosition = "overlayPosition"
    /// Points from the edges of the visible frame the HUD is anchored to.
    static let overlayMargin = "overlayMargin"
    static let overlayDisplay = "overlayDisplay"
    static let overlaySize = "overlaySize"
    /// Percent, 30 to 100.
    static let overlayOpacity = "overlayOpacity"
    static let tintsOverlay = "tintsOverlay"
    static let lockedLayerOverlay = "lockedLayerOverlay"
    /// What typing on a layer does to its full overlay (ADRs 0064, 0065); it keeps showing by default.
    static let overlayTyping = "overlayTyping"
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
    var hud: OverlayHUD?
    @AppStorage(SettingsKey.showsKeyPresses) private var showsPresses = true
    @AppStorage(SettingsKey.followsKeyboardOnConnect) private var follows = true

    /// Without `recorder`, each layer's shortcut shows as text; without `overlay`, the overlay can't be previewed.
    public init(layerShortcuts: LayerShortcuts? = nil, recorder: LayerShortcutRecorder? = nil, overlay: OverlayHUD? = nil) {
        self.layerShortcuts = layerShortcuts
        self.recorder = recorder
        self.hud = overlay
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
            OverlaySection(hud: hud)
            if let layerShortcuts { LayerShortcutsSection(shortcuts: layerShortcuts, recorder: recorder) }
        }
        .formStyle(.grouped)
        // Leaving the pane, for another tab or by closing Settings, ends the preview.
        .onDisappear { hud?.isPreviewing = false }
    }
}

/// The overlay HUD's options (spec §8.4, ADRs 0045 and 0062), with the defaults ``OverlaySettings`` declares too, and a
/// Preview that shows the overlay with them.
private struct OverlaySection: View {
    var hud: OverlayHUD?
    @AppStorage(SettingsKey.showsOverlay) private var showsOverlay = true
    @AppStorage(SettingsKey.overlayPosition) private var position = OverlayPosition.bottom
    @AppStorage(SettingsKey.overlayMargin) private var margin = 72
    @AppStorage(SettingsKey.overlayDisplay) private var display = OverlayDisplay.pointer
    @AppStorage(SettingsKey.overlaySize) private var size = OverlaySize.medium
    @AppStorage(SettingsKey.overlayOpacity) private var opacity = 100
    @AppStorage(SettingsKey.overlayDelay) private var delay = 150
    @AppStorage(SettingsKey.tintsOverlay) private var tints = false
    @AppStorage(SettingsKey.lockedLayerOverlay) private var locked = LockedLayerOverlay.reminder
    @AppStorage(SettingsKey.overlayTyping) private var typing = OverlayTyping.keepShowing

    var body: some View {
        Section {
            Toggle("Show overlay while a layer is held", isOn: $showsOverlay)
            Group {
                preview
                placement
                Picker("Size", selection: $size) {
                    Text("Small").tag(OverlaySize.small)
                    Text("Medium").tag(OverlaySize.medium)
                    Text("Large").tag(OverlaySize.large)
                }
                .pickerStyle(.segmented)
                SteppedSlider(
                    title: "Opacity", value: $opacity, range: OverlaySettings.opacities, step: 5, tick: 10,
                    text: String(localized: "\(opacity)%"))
                SteppedSlider(
                    title: "Delay", value: $delay, range: OverlaySettings.delays, step: 10, tick: 250,
                    text: String(localized: "\(delay) ms"))
                Picker("When you type on the layer", selection: $typing) {
                    Text("Keep showing").tag(OverlayTyping.keepShowing)
                    Text("Hide until you pause").tag(OverlayTyping.hideUntilPause)
                    Text("Hide until the next hold").tag(OverlayTyping.hideUntilNextHold)
                }
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
                layer. Typing on the layer can hide it until you pause for the delay, or until you let go of the layer \
                and hold it again. Turn on Live View from Sextant in the menu bar or a layout window’s toolbar. \
                Preview shows the overlay with these settings for a few seconds, even with Live View off.
                """
            )
            .foregroundStyle(.secondary)
        }
    }

    /// Where it goes: the spot, how far from the screen's edges, and on which display.
    @ViewBuilder private var placement: some View {
        LabeledContent("Position") {
            HStack(spacing: 12) {
                // The picker's spots tell VoiceOver which one is chosen.
                Text(position.title).foregroundStyle(.secondary).accessibilityHidden(true)
                OverlayPositionPicker(selection: $position)
            }
        }
        // The centre spot is in the middle both ways, so no edge is near it.
        SteppedSlider(
            title: "Distance from edge", value: $margin, range: OverlaySettings.margins, step: 1, tick: 50,
            text: String(localized: "\(margin) pt")
        )
        .disabled(position == .center)
        Picker("Display", selection: $display) {
            Text("Follows the pointer").tag(OverlayDisplay.pointer)
            Text("Main display").tag(OverlayDisplay.main)
        }
    }

    /// Shows the overlay with these settings until it is clicked again, 8 s after the last change, or the pane closes.
    private var preview: some View {
        LabeledContent {
            Button {
                hud?.isPreviewing.toggle()
            } label: {
                Text(hud?.isPreviewing == true ? "Stop Preview" : "Preview")
            }
            .disabled(hud == nil)
        } label: {
            Text("See the overlay with these settings")
        }
    }
}

/// A setting's slider in whole steps of `step`, with a tick every `tick` and the value beside it. The binding rounds to
/// the step itself: `step:` would draw a tick per step, which run together into a dotted line.
private struct SteppedSlider: View {
    var title: LocalizedStringKey
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step: Int
    var tick: Int
    /// The value as the pane shows it: "150 ms".
    var text: String

    var body: some View {
        let bounds = Double(range.lowerBound)...Double(range.upperBound)
        LabeledContent(title) {
            HStack {
                Slider(value: Binding(get: { Double(value) }, set: { value = Int(($0 / Double(step)).rounded()) * step }), in: bounds) {
                    Text(title)
                } ticks: {
                    SliderTickContentForEach(
                        Array(stride(from: bounds.lowerBound, through: bounds.upperBound, by: Double(tick))), id: \.self,
                        content: SliderTick.init)
                }
                .labelsHidden()
                .accessibilityValue(text)
                Text(verbatim: text).monospacedDigit().foregroundStyle(.secondary).frame(width: 60, alignment: .trailing)
            }
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
