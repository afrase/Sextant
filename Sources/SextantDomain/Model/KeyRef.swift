import Foundation

/// A key on a layer, optionally one slot of it: what issues, diagnostics and the source map point at.
public struct KeyRef: Hashable, Sendable {
    public var layer: Int
    public var index: Int
    public var slot: KeySlot?

    public init(layer: Int, index: Int, slot: KeySlot? = nil) {
        self.layer = layer
        self.index = index
        self.slot = slot
    }
}
