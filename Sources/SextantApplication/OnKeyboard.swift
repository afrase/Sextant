import Foundation
import Observation
import SextantDomain
import os

/// Which library layout the keyboard runs, as it was flashed (ADR 0039). App-wide. It reads only the USB serial, so it
/// works with live access off, and it never shows edits made since the flash as being on the keyboard.
@MainActor
@Observable
public final class OnKeyboard {
    public struct Running: Equatable, Sendable {
        public let entry: LibraryEntry
        /// Nil when only the working copy matches: the flash's revision isn't recorded yet, or recording it failed.
        /// Compare it by `id`: storage keeps `createdAt` to the second, so a summary read back can differ in its date.
        public let revision: RevisionSummary?
        public let layout: KeyboardLayout
    }

    /// Nil without a keyboard, or when it runs a layout or a version the library doesn't hold.
    public private(set) var running: Running?

    @ObservationIgnored private let library: Library
    @ObservationIgnored private let store: any LayoutLibrary
    @ObservationIgnored private let live: LiveSession
    @ObservationIgnored private var task: Task<Void, Never>?
    private static let log = Logger(subsystem: "com.sextant.app", category: "application")

    public init(library: Library, store: any LayoutLibrary, live: LiveSession) {
        self.library = library
        self.store = store
        self.live = live
    }

    /// Follows the keyboard's serial, library refreshes and flashes for the app's lifetime.
    public func start() {
        guard task == nil else { return }
        let (library, live) = (library, live)
        task = Task {
            var flashed: UUID?
            // A flash records its revision before it lets go of flash mode, so the release picks the revision up.
            for await (serial, entries, flashing) in Observations({ (live.firmwareSerial, library.entries, live.flashingLayoutID) }) {
                flashed = flashing ?? flashed
                let found = await Self.resolve(serial, entries: entries, flashed: flashed, store: store)
                if found != running { running = found }
            }
        }
    }

    /// An Oryx serial names an import revision. A Sextant serial names the working copy when it has the same
    /// fingerprint (the same content), otherwise the newest flash revision that has it.
    /// - Parameter flashed: the entry Sextant flashed last, which wins when two entries claim one Oryx serial (the same
    ///   layout imported twice); otherwise the first of `entries` does.
    static func resolve(_ serial: String?, entries: [LibraryEntry], flashed: UUID? = nil, store: any LayoutLibrary) async -> Running? {
        guard let serial else { return nil }
        for entry in entries.filter({ $0.id == flashed }) + entries.filter({ $0.id != flashed }) where entry.isOnKeyboard(serial: serial) {
            let stored: StoredLayout
            do {
                stored = try await store.load(entry.id)
            } catch {
                log.error("Layout unreadable: \(String(describing: error), privacy: .public)")
                continue
            }
            if FirmwareIdentity(layout: stored.layout, libraryID: entry.id, importedLayout: nil).serial == serial {
                let revision = stored.revisions.last { $0.source == .flash && $0.contentHash == stored.contentHash }
                return Running(entry: entry, revision: revision, layout: stored.layout)
            }
            let found = await FirmwareIdentity.revision(
                runningSerial: serial, of: entry.id, origin: entry.origin, revisions: stored.revisions, library: store)
            if let found { return Running(entry: entry, revision: found.summary, layout: found.layout) }
        }
        return nil
    }
}
