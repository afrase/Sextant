import SextantApplication
import SextantDomain
import SwiftUI

/// Keyboard ▸ Move Keyboard to Layer, and the same menu in the Device popover (spec §9.1, ADR 0048). It lists the layers
/// of the layout on the keyboard, checks the one it's on, and moves it to the one chosen. While it can't (Live View off,
/// still connecting), the items are disabled under a heading that says why; a heading also says why a layout Sextant
/// doesn't have offers only layer 0.
struct MoveKeyboardToLayerMenu: View {
    var onKeyboard: OnKeyboard?
    var live: LiveSession?
    /// Shows the global shortcuts on the items (the main menu only; a popover's menu keeps no key equivalents).
    var shortcuts: LayerShortcuts?

    var body: some View {
        Menu("Move Keyboard to Layer") {
            if let onKeyboard {
                let items = layers(onKeyboard)
                if let heading = Self.heading(onKeyboard) {
                    Section(heading.text) { layerItems(items, onKeyboard: onKeyboard).disabled(!heading.enabled) }
                } else {
                    layerItems(items, onKeyboard: onKeyboard)
                }
            }
        }
        .disabled(onKeyboard == nil)
    }

    private func layerItems(_ items: [(layer: Int, title: String)], onKeyboard: OnKeyboard) -> some View {
        ForEach(items, id: \.layer) { item in
            Toggle(
                item.title,
                isOn: Binding(
                    get: { live?.activeLayer == item.layer },
                    // Choosing the layer it's on moves it there again, which is harmless.
                    set: { _ in try? onKeyboard.moveKeyboard(toLayer: item.layer) })
            )
            .keyboardShortcut(shortcuts?.menuShortcut(forLayer: item.layer).flatMap(\.swiftUI))
        }
    }

    /// The layers of the layout the keyboard runs; only layer 0 when Sextant doesn't have it, and none without a
    /// keyboard.
    private func layers(_ onKeyboard: OnKeyboard) -> [(layer: Int, title: String)] {
        let layout = onKeyboard.running?.layout
        guard layout != nil || Self.refusal(onKeyboard, layer: 0) != .noKeyboard else { return [] }
        return Self.reachableLayers(layout).map { ($0.index, $0.title) }
    }

    /// The layers a move can reach: the layout's first 32 (ADR 0038), or only layer 0 for a layout Sextant doesn't have.
    /// This menu and the menu bar panel list these.
    nonisolated static func reachableLayers(_ layout: KeyboardLayout?) -> [(index: Int, title: String, color: HexColor?)] {
        guard let layout else { return [(0, String(localized: "Layer 0"), nil)] }
        return layout.layers.prefix(32).enumerated().map { ($0.offset, $0.element.title, $0.element.color) }
    }

    /// The heading over the items: why they're disabled, or why a layout Sextant doesn't have offers only layer 0; nil
    /// over a known layout's layers.
    static func heading(_ onKeyboard: OnKeyboard) -> (text: String, enabled: Bool)? {
        if let refusal = refusal(onKeyboard, layer: 0) { return (refusal.localizedDescription, false) }
        return onKeyboard.running == nil ? (LayerMoveRefusal.unknownLayout.localizedDescription, true) : nil
    }

    /// Why moving to `layer` would send nothing; nil when it would send. Asks without sending.
    static func refusal(_ onKeyboard: OnKeyboard, layer: Int) -> LayerMoveRefusal? {
        do {
            try onKeyboard.moveKeyboard(toLayer: layer, dryRun: true)
            return nil
        } catch {
            return error
        }
    }
}

extension HotKeyShortcut {
    /// The menu item's key equivalent; nil for a key a menu can't show.
    var swiftUI: KeyboardShortcut? {
        guard let key = keyEquivalent, key.count == 1, let character = key.first else { return nil }
        var flags: EventModifiers = []
        if modifiers.contains(.control) { flags.insert(.control) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.command) { flags.insert(.command) }
        return KeyboardShortcut(KeyEquivalent(character), modifiers: flags, localization: .custom)
    }
}
