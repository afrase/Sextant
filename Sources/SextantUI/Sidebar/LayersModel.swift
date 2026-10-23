import Observation

/// Layer management's window state (spec §6.1): the in-place rename, and the layer confirmations the sidebar, the
/// Layer menu and the inspector open. The edits themselves are `EditSession` calls on the window.
@MainActor
@Observable
final class LayersModel {
    /// The layer whose name the sidebar is editing in place, by id.
    var renamingID: String?
    /// A layer waiting for Clear Layer's confirmation.
    var pendingClear: Int?
    /// A layer whose deletion waits for confirmation because keys still switch to it.
    var pendingDeletion: Int?
}
