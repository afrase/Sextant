import Observation

/// File ▸ Export's window state (spec §9.1): the one file waiting for its save panel, or why it couldn't be made or
/// saved. The Heatmap's exports share it, so one panel is up at a time.
@MainActor
@Observable
final class ExportModel {
    var pending: PendingExport?
}
