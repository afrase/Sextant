import Foundation

/// How to reach the layout's Reset key (QK_BOOT) from the base layer (spec §7.3, flash-mode card B):
/// the holds to press, in order, then the Reset key itself.
public struct FlashPath: Hashable, Sendable {
    /// Layer-hold keys to hold, starting on layer 0 (e.g. Space, key 51, which holds Brd+Sys).
    public var holds: [KeyRef]
    /// The Reset key.
    public var reset: KeyRef

    public init(holds: [KeyRef], reset: KeyRef) {
        self.holds = holds
        self.reset = reset
    }

    /// The shortest reachable path to a `QK_BOOT` key, or nil when the layout has none reachable.
    ///
    /// Searches layers breadth-first from layer 0 through momentary-layer holds (`MO`, or `LT`'s hold); every key on
    /// the path is a different physical key, since all of them are down at once.
    public static func find(in layout: KeyboardLayout) -> Self? {
        var queue: [(layer: Int, holds: [KeyRef])] = [(0, [])]
        // A layer is worth revisiting with other keys held (the Reset key may sit under the first hold found), so a
        // state is the layer plus the held key indices.
        var seen: Set<[Int]> = [[0]]
        var next = 0
        while next < queue.count {
            let (layer, holds) = queue[next]
            next += 1
            guard layout.layers.indices.contains(layer) else { continue }
            let free = layout.layers[layer].keys.enumerated().filter { i, _ in !holds.contains { $0.index == i } }
            if let (index, _) = free.first(where: { $0.element.tap?.canonicalCode == "QK_BOOT" }) {
                return Self(holds: holds, reset: KeyRef(layer: layer, index: index, slot: .tap))
            }
            for (index, key) in free {
                // A hold slot holds; a lone tap slot holds too (a plain MO key). A tap dance's tap doesn't.
                let slot: KeySlot = key.hold != nil ? .hold : .tap
                guard slot == .hold || (key.doubleTap == nil && key.tapHold == nil), let action = key[slot],
                    action.canonicalCode == "MO", let target = action.layer,
                    // Bounded, so a pathological imported layout can't stall the search.
                    seen.count < 4096, seen.insert([target] + (holds.map(\.index) + [index]).sorted()).inserted
                else { continue }
                queue.append((target, holds + [KeyRef(layer: layer, index: index, slot: slot)]))
            }
        }
        return nil
    }
}
