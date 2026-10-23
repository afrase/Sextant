import Observation
import SextantDomain

/// The window's device and Build & Flash presentation state (spec §7, §8.2): the sheet and its log, the Device popover,
/// and the stand-ins a window without a live session shows (tests, snapshots). The Build & Flash run itself is the
/// window's `buildFlash`, made per layout.
@MainActor
@Observable
final class DeviceModel {
    /// The Build & Flash sheet is up. Hide takes it down while the run goes on (spec §7.6).
    var showsBuildSheet = false
    /// Stop, Cancel or Done took the sheet down: the run stops once the sheet has gone, so it doesn't show the first
    /// step as it leaves.
    @ObservationIgnored var stopsBuildWhenSheetCloses = false
    /// The sheet's build log is expanded (⇧⌘B).
    var showsBuildLog = false
    /// Where the Device popover hangs while it is open (spec §8.2).
    var popover: DevicePopoverAnchor?
    /// The layout of the latest import revision, which the keyboard's serial is matched against (ADR 0019).
    var importedLayout: KeyboardLayout?
    /// The window's `keyboardLayoutPrompt` where nothing reads the keyboard's layout (tests, snapshots).
    var fixedKeyboardLayoutPrompt: KeyboardLayoutPrompt?
    /// Follow where there is no live session (tests, snapshots).
    var followsWithoutLive = false
    /// The window's `activity` where there is no live session (tests, snapshots).
    var fixedActivity = ActivityState()
}
