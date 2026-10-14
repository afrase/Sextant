import Foundation
import SextantDomain

/// Where the Heatmap's hourly counts are kept: on this Mac, per library layout, outside its package so exports and
/// duplicates never carry typing data (ADR 0053).
public protocol HeatmapStore: Sendable {
    /// The stored hours of a layout from `start` on (all of them when nil), oldest first. A damaged file reads as no
    /// hours.
    func hours(of layoutID: UUID, from start: Date?) async throws(HeatmapStoreError) -> [HeatmapHour]
    /// Adds counts to what is stored for their hours.
    func add(_ hours: [HeatmapHour], to layoutID: UUID) async throws(HeatmapStoreError)
    /// Deletes every hour before `date`, for every layout.
    func prune(before date: Date) async throws(HeatmapStoreError)
    /// Deletes a layout's counts, or every layout's when nil.
    func clear(_ layoutID: UUID?) async throws(HeatmapStoreError)
}

/// Why the Heatmap's counts couldn't be read or written.
public enum HeatmapStoreError: Error, Equatable, Sendable, LocalizedError {
    /// The detail is for the log.
    case io(String)

    public var errorDescription: String? {
        String(localized: "Sextant couldn’t save or read the heatmap. Check that the disk has space and try again.")
    }
}
