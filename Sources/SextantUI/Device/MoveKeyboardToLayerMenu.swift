import SextantApplication
import SextantDomain
import SwiftUI

/// Keyboard ▸ Move Keyboard to Layer, and the same menu in the Device popover (spec §9.1, ADR 0048). It lists the layers
/// of the layout on the keyboard, checks the one it's on, and moves it to the one chosen. While it can't (Live View off,
/// still connecting), the items are disabled under a heading that says why.
struct MoveKeyboardToLayerMenu: View {
    var onKeyboard: OnKeyboard?
    var live: LiveSession?
    /// Shows the global shortcuts on the items (the main menu only; a popover's menu keeps no key equivalents).
    var shortcuts: LayerShortcuts?

    var body: some View {
        Menu("Move Keyboard to Layer") {
            if let onKeyboard {
                let refusal = Self.refusal(onKeyboard, layer: 0)
                let items = layers(onKeyboard)
                if let refusal {
                    Section(refusal.localizedDescription) { layerItems(items, onKeyboard: onKeyboard).disabled(true) }
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
        if let layout = onKeyboard.running?.layout {
            return layout.layers.prefix(32).enumerated().map { ($0.offset, $0.element.title) }
        }
        return Self.refusal(onKeyboard, layer: 0) == .noKeyboard ? [] : [(0, String(localized: "Layer 0"))]
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
