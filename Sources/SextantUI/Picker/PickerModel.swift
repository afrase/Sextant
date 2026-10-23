import Observation
import SextantDomain

/// The command palette's and keycode picker's own state (spec §5.6, §5.7): what they remember between opens, and the
/// panel plumbing. Which panel is open is the window's `palette`, one of its input modes.
@MainActor
@Observable
final class PickerModel {
    /// Keycodes assigned from the picker and commands run from the palette, newest first (Suggested, Recent).
    var recentKeycodes: [KeyAction] = []
    var recentCommands: [String] = []
    /// Bumped when a closed panel hands keyboard focus back to the board.
    var boardFocusRequests = 0
    /// The mouse event number of the click that last closed the palette from outside it (the toolbar's Search toggles).
    var paletteDismissingClick: Int?
}
