import Foundation

/// Why the keyboard is on a layer, as far as the live view can tell (spec §8.4).
///
/// The keyboard reports only its highest active layer and the physical keys held down, never what turned a layer on,
/// so this is inferred: a key held down whose action holds the layer on means the layer goes away when it is let go.
public enum LayerHold: Hashable, Sendable {
    /// The base layer.
    case base
    /// A key held down holds the layer on (by key index): MO, the hold of a layer-tap (LT), LM, or a TT or OSL key
    /// while it is down. The layer ends when that key is let go (an OSL key's layer lasts one more key).
    case momentary(heldBy: Int)
    /// Nothing held explains the layer: TG, TO, DF, a tapped TT, a tap dance's TO, or a move the host sent. It stays
    /// until something else moves the keyboard.
    case locked
    /// The Navigator's auto-mouse layer, which the firmware turns on while the pointer moves and off soon after.
    case pointer

    /// Actions that turn their layer on only while their key is down.
    static let holdingCodes: Set<String> = ["MO", "LM", "TT", "OSL"]

    /// Classifies `layer`, the keyboard's highest active layer, from the keys held down.
    /// - Parameter pressed: each key held down, by index, with the keyboard's highest layer when it went down. The
    ///   firmware chose the key's action on that layer, falling through transparent keys to the base layer the way the
    ///   board shows it (``KeyboardLayout/resolvedKey(layer:index:activeLayers:)``). With several holders, the lowest
    ///   key index wins.
    public static func classify(layout: KeyboardLayout, layer: Int, pressed: [Int: Int]) -> Self {
        guard layer > 0 else { return .base }
        let holder = pressed.keys.sorted().first {
            holdingAction(layout: layout, layer: layer, index: $0, pressedOn: pressed[$0] ?? layer) != nil
        }
        if let holder { return .momentary(heldBy: holder) }
        return layout.navigator != nil && layout.automouseLayer == layer ? .pointer : .locked
    }

    /// The action of the key at `index`, pressed while `pressedOn` was the highest layer, that holds `layer` on while
    /// the key is down; nil when it has none.
    public static func holdingAction(layout: KeyboardLayout, layer: Int, index: Int, pressedOn: Int) -> KeyAction? {
        let key = layout.resolvedKey(layer: pressedOn, index: index).effective
        return key.actions.lazy.map(\.action).first { holdingCodes.contains($0.canonicalCode) && $0.layer == layer }
    }
}
