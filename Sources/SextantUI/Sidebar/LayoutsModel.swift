import Foundation
import Observation

/// The library rows' window state (spec §2.3, §3.6): which layout's Rename… alert or Move to Trash… confirmation is
/// up. The actions themselves go through the window and `Library`.
@MainActor
@Observable
final class LayoutsModel {
    /// The layout whose Rename… alert is showing.
    var pendingRename: UUID?
    /// The layout whose Move to Trash… confirmation is showing.
    var pendingTrash: UUID?
}
