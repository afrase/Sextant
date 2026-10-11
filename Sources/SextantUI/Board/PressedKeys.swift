import Observation

/// Live pressed keys, one observable per key, so a press redraws only its own cap (spec §13.3 item 6).
/// The live session feeds it a set of key indices; the board reads one key's state per cap.
@MainActor
public final class PressedKeys {
    @MainActor
    @Observable
    final class KeyState {
        fileprivate(set) var isDown = false
    }

    private var states: [Int: KeyState] = [:]

    public init() {}

    /// Marks exactly `indices` as down; only keys whose state changes notify their cap.
    public func update(_ indices: Set<Int>) {
        for (index, state) in states where state.isDown != indices.contains(index) { state.isDown.toggle() }
        for index in indices where states[index] == nil { state(index).isDown = true }
    }

    func state(_ index: Int) -> KeyState {
        if let state = states[index] { return state }
        let state = KeyState()
        states[index] = state
        return state
    }
}
