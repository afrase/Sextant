import Foundation
import Observation

/// The Firmware Settings page's own state (spec §8.8): its search, the Modified only filter and the animation list.
@MainActor
@Observable
public final class FirmwareSettingsModel {
    /// The search field's text; empty shows every setting.
    public var query = ""
    /// Shows only settings changed from their defaults.
    public var modifiedOnly = false
    /// The RGB section's list of animations is open.
    public var showsAnimations = false
    /// Bumped by ⌘F (Edit ▸ Find Setting…) to put focus in the search field.
    var searchFocusRequests = 0

    var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    func clearFilters() {
        query = ""
        modifiedOnly = false
    }
}
