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
    public static func find(in layout: KeyboardLayout) -> Self? {
        nil  // Implemented in the build slice.
    }
}
