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
    /// The serial ``running`` was last resolved for, set after each resolve; nil without one. While it isn't the keyboard's
    /// serial, that serial is still being looked up, so a nil ``running`` doesn't yet mean the library lacks it.
    public private(set) var resolvedSerial: String?
    /// Bumped by ``refresh()``, which the resolve loop observes.
    private var refreshes = 0

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
            let changes = Observations({ (live.firmwareSerial, library.entries, live.flashingLayoutID, self.refreshes) })
            // A flash records its revision before it lets go of flash mode, so the release picks the revision up.
            for await (serial, entries, flashing, _) in changes {
                flashed = flashing ?? flashed
                let found = await Self.resolve(serial, entries: entries, flashed: flashed, store: store)
                if found != running { running = found }
                if serial != resolvedSerial { resolvedSerial = serial }
            }
        }
    }

    /// Resolves the keyboard's layout again: after a change ``Library/entries`` doesn't show, such as a revision added to
    /// a layout (the keyboard's layout read back from it, ADR 0061).
    public func refresh() { refreshes += 1 }

    /// Moves the keyboard to `layer` (`04 01 n`, ADR 0038), only over a paired Live View session (ADR 0057) and only to
    /// a layer of the layout it runs: layer 0 alone when Sextant doesn't hold that layout, since a layer past the build's
    /// layer state drops the keyboard to its default layer (ADR 0048). With `dryRun`, only says why it wouldn't send.
    public func moveKeyboard(toLayer layer: Int, dryRun: Bool = false) throws(LayerMoveRefusal) {
        switch live.connection {
        case .noKeyboard: throw .noKeyboard
        case .bootloader: throw .flashMode
        case .liveOff: throw .liveOff
        case .heldByAnotherApp: throw .heldByAnotherApp
        case .connected: if !live.canSend { throw .connecting }
        }
        guard layer >= 0, layer < (running?.layout.layers.count ?? 1) else {
            throw running == nil ? .unknownLayout : .noSuchLayer(layer)
        }
        guard !dryRun else { return }
        do throws(DeviceError) { try live.send(.moveToLayer(layer)) } catch { throw LayerMoveRefusal(error, layer: layer) }
    }

    /// An Oryx serial names an import revision. A Sextant serial of the layout's id or one of its aliases (ADR 0061) names
    /// the working copy when it has the same fingerprint (the same content), otherwise the newest flash revision that has it.
    /// - Parameter flashed: the entry Sextant flashed last, which wins when two entries claim one Oryx serial (the same
    ///   layout imported twice); otherwise the first of `entries` does.
    static func resolve(_ serial: String?, entries: [LibraryEntry], flashed: UUID? = nil, store: any LayoutLibrary) async -> Running? {
        guard let serial else { return nil }
        let fingerprint = FirmwareIdentity.sextantFingerprint(of: serial)
        for entry in entries.filter({ $0.id == flashed }) + entries.filter({ $0.id != flashed }) where entry.isOnKeyboard(serial: serial) {
            let stored: StoredLayout
            do {
                stored = try await store.load(entry.id)
            } catch {
                log.error("Layout unreadable: \(String(describing: error), privacy: .public)")
                continue
            }
            // On the keyboard, a Sextant serial names this layout's id or an alias: the fingerprint alone says which content.
            if let fingerprint, FirmwareIdentity.fingerprint(of: stored.layout) == fingerprint {
                let revision = stored.revisions.last { $0.source == .flash && $0.contentHash == stored.contentHash }
                return Running(entry: entry, revision: revision, layout: stored.layout)
            }
            let found = await FirmwareIdentity.revision(
                runningSerial: serial, of: entry.id, aliases: entry.aliases, origin: entry.origin, revisions: stored.revisions,
                library: store)
            if let found { return Running(entry: entry, revision: found.summary, layout: found.layout) }
        }
        return nil
    }
}
