import Foundation
import Observation
import SextantDomain
import os

/// Why the keyboard's layout couldn't be read back or put in the library (ADR 0061).
public enum PullFailure: Error, Equatable, Sendable, LocalizedError {
    case keyboard(LayoutReadError)
    case record(LayoutRecordError)
    /// The stored layout isn't the one the keyboard's serial names.
    case mismatch
    case library(LibraryError)

    public var errorDescription: String? {
        switch self {
        case let .keyboard(e): e.localizedDescription
        case let .record(e): e.localizedDescription
        case .mismatch: String(localized: "The layout stored in the keyboard doesn't match the firmware it runs.")
        case let .library(e): e.localizedDescription
        }
    }
}

/// Reads the layout a Sextant build stores in the keyboard (ADR 0061) when the library doesn't have the version the
/// keyboard runs, and puts it in the library: by itself when a library layout is linked to it, else where the user
/// chooses. App-wide; the composition root builds and starts it.
///
/// Reading changes nothing on the keyboard and goes only over a Live View session the user paired (ADR 0057). The
/// layout's content is never logged: it holds macro text (ADR 0042).
@MainActor
@Observable
public final class KeyboardLayoutPull {
    public enum Status: Equatable, Sendable {
        case idle
        /// Reading; the fraction read so far.
        case reading(Double)
        /// The keyboard's firmware stores no layout.
        case noRecord
        /// Read, and no library layout is linked to it: ``add(to:)`` puts it where the user chooses.
        case found(Found)
        /// Put in the library.
        case added(Added)
        case failed(PullFailure)
    }

    public struct Found: Equatable, Sendable {
        public let layout: KeyboardLayout
        public let serial: String
        /// The library layout it most likely is: the same Oryx layout, else the same title. Nil when none.
        public let suggested: UUID?

        public init(layout: KeyboardLayout, serial: String, suggested: UUID?) {
            self.layout = layout
            self.serial = serial
            self.suggested = suggested
        }

        /// Whether ``KeyboardLayoutPull/add(to:)`` can put it in `entry`. Sextant's build of an Oryx revision goes only in a
        /// layout from that Oryx layout, or in a new one; a Sextant build's layout can go in any.
        public func fits(_ entry: LibraryEntry) -> Bool { entry.takesKeyboardLayout(serial: serial) }
    }

    public struct Added: Equatable, Sendable {
        public let entryID: UUID
        public let revision: RevisionSummary?
        /// The keyboard's layout also became the working copy.
        public let adopted: Bool

        public init(entryID: UUID, revision: RevisionSummary?, adopted: Bool) {
            self.entryID = entryID
            self.revision = revision
            self.adopted = adopted
        }
    }

    public private(set) var status: Status = .idle

    /// A verified record: the layout it holds, the serial it was read for, and the revision source it gets.
    struct Pending: Sendable {
        var record: LayoutRecord
        var layout: KeyboardLayout
        var serial: String
        var source: RevisionSource
    }

    /// What the automatic read follows.
    private struct Inputs: Equatable, Sendable {
        var serial: String?
        var canSend: Bool
        var hasKeyboard: Bool
        var isFlashing: Bool
        var resolvedSerial: String?
        var isKnown: Bool

        @MainActor init(live: LiveSession, onKeyboard: OnKeyboard) {
            serial = live.firmwareSerial
            canSend = live.canSend
            hasKeyboard = live.connection != .noKeyboard
            isFlashing = live.flashingLayoutID != nil
            resolvedSerial = onKeyboard.resolvedSerial
            isKnown = onKeyboard.running != nil
        }
    }

    /// How long ``read(startingLiveView:)`` waits for Live View to pair. Tests that run on real time lengthen it.
    @ObservationIgnored public var pairingWait = Duration.seconds(3)

    @ObservationIgnored private let live: LiveSession
    @ObservationIgnored private let onKeyboard: OnKeyboard
    @ObservationIgnored private let library: Library
    @ObservationIgnored private let store: any LayoutLibrary
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Serials read since the keyboard connected: a read that failed or found no record isn't repeated by itself.
    @ObservationIgnored private var readSerials: Set<String> = []
    /// The serial ``status`` is about.
    @ObservationIgnored private var statusSerial: String?
    /// A serial whose found layout or failure was dismissed: not read by itself again until the keyboard reports another.
    @ObservationIgnored private var dismissedSerial: String?
    /// The record behind a ``Status/found(_:)``.
    @ObservationIgnored private var pending: Pending?
    @ObservationIgnored private var isAdding = false
    /// Reads begun since launch. A read can ask for a part twice when its reply is late, so the requests the keyboard
    /// gets don't count reads.
    @ObservationIgnored private(set) var readsStarted = 0
    /// The inputs the automatic read last followed.
    @ObservationIgnored private var followed: Inputs?
    private static let log = Logger(subsystem: "com.sextant.app", category: "application")

    /// - Parameter clock: times the wait for Live View to pair (injected for tests).
    public init(
        live: LiveSession, onKeyboard: OnKeyboard, library: Library, store: any LayoutLibrary,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.live = live
        self.onKeyboard = onKeyboard
        self.library = library
        self.store = store
        self.clock = clock
    }

    /// Reads by itself from now on: once per serial while the keyboard stays connected, when Live View is paired, the
    /// keyboard's serial has been looked up and the library doesn't have what it runs. Never while flashing.
    public func start() {
        guard task == nil else { return }
        let (live, onKeyboard) = (live, onKeyboard)
        task = Task { [weak self] in
            for await now in Observations({ Inputs(live: live, onKeyboard: onKeyboard) }) {
                self?.follow(now)
            }
        }
    }

    /// Reads the keyboard's layout now (Get Layout from Keyboard). With `startingLiveView`, turns Live View on first
    /// (the user's click is the consent, ADR 0057) and waits up to 3 s for it to pair.
    public func read(startingLiveView: Bool = false) async {
        guard !isBusy else { return }
        statusSerial = live.firmwareSerial
        if startingLiveView, !live.canSend {
            status = .reading(0)
            guard await pairs() else { return fail(.keyboard(.notLive)) }
        }
        guard live.canSend else { return fail(.keyboard(.notLive)) }
        // The record is checked against the serial; firmware without one can't be checked.
        guard let serial = live.firmwareSerial else { return fail(.mismatch) }
        readSerials.insert(serial)
        dismissedSerial = nil
        await pull(serial)
    }

    /// Puts a found layout in the library: as a new revision of `entryID` that becomes its working copy (unsaved edits
    /// checkpointed first, undoable in an open window), or as a new layout when nil. Links the record's ids either way.
    public func add(to entryID: UUID?) async {
        guard case let .found(found) = status, let pending, !isAdding else { return }
        // A layout it doesn't fit would never read as on the keyboard; the window doesn't offer one.
        if let entryID, let entry = library.entries.first(where: { $0.id == entryID }), !found.fits(entry) {
            Self.log.error("Not adding the keyboard's layout to \(entryID, privacy: .public): it doesn't fit there")
            return
        }
        isAdding = true
        defer { isAdding = false }
        do throws(LibraryError) {
            let added = if let entryID { try await adopt(pending, into: entryID) } else { try await create(pending) }
            await finish(added)
        } catch {
            fail(.library(error))
        }
    }

    /// Forgets a found layout or a failure until the keyboard's serial changes.
    public func dismiss() {
        guard !isBusy else { return }
        switch status {
        case .found, .failed, .noRecord: dismissedSerial = statusSerial
        case .idle, .reading, .added: break
        }
        pending = nil
        status = .idle
    }

    // MARK: Reading

    private var isBusy: Bool {
        if case .reading = status { return true }
        return isAdding
    }

    /// Whether the automatic read has followed the inputs as they are now: tests wait for it before checking that
    /// nothing was read.
    var isCaughtUp: Bool { followed == Inputs(live: live, onKeyboard: onKeyboard) }

    private func follow(_ now: Inputs) {
        followed = now
        // Another keyboard, or the same one back, is read again.
        if !now.hasKeyboard { readSerials = [] }
        if let serial = now.serial {
            if serial != dismissedSerial { dismissedSerial = nil }
            // What was learnt about another serial no longer describes the keyboard.
            if serial != statusSerial, !isBusy { forget() }
        }
        guard let serial = now.serial, now.canSend, !now.isFlashing, !now.isKnown, now.resolvedSerial == serial,
            !readSerials.contains(serial), serial != dismissedSerial, !isBusy
        else { return }
        readSerials.insert(serial)
        // Busy at once, so the next change doesn't start another read before this one begins.
        statusSerial = serial
        status = .reading(0)
        // Apart from the loop that follows the inputs, so an unplug mid-read still clears readSerials. Changes while it ran
        // were followed busy, so it follows the inputs as they are once it ends.
        Task { [weak self] in
            await self?.pull(serial)
            guard let self else { return }
            follow(Inputs(live: live, onKeyboard: onKeyboard))
        }
    }

    private func forget() {
        statusSerial = nil
        pending = nil
        if status != .idle { status = .idle }
    }

    /// Turns Live View on and waits up to ``pairingWait`` for it to pair.
    private func pairs() async -> Bool {
        live.startLive()
        let (live, clock, wait) = (live, clock, pairingWait)
        let (outcomes, outcome) = AsyncStream.makeStream(of: Bool.self)
        let paired = Task {
            for await canSend in Observations({ live.canSend }) where canSend {
                outcome.yield(true)
                return
            }
        }
        let timeout = Task {
            try? await clock.sleep(for: wait)
            outcome.yield(false)
        }
        defer {
            paired.cancel()
            timeout.cancel()
        }
        for await isPaired in outcomes { return isPaired }
        return false
    }

    /// Reads the record the firmware stores for `serial`, checks it is what the serial names, and puts it in the library
    /// layout linked to it, or offers it.
    private func pull(_ serial: String) async {
        readsStarted += 1
        statusSerial = serial
        pending = nil
        status = .reading(0)
        let bytes: [UInt8]
        do throws(LayoutReadError) {
            bytes = try await live.readLayoutRecord { [weak self] fraction in self?.progressed(fraction) }
        } catch {
            if error == .noRecord { noRecord() } else { fail(.keyboard(error)) }
            return
        }
        let checked: Pending
        do throws(PullFailure) {
            checked = try Self.verified(bytes, serial: serial)
        } catch {
            return fail(error)
        }
        if let entry = linked(checked) {
            await addLinked(checked, to: entry)
        } else {
            pending = checked
            let fitting = library.entries.filter { $0.takesKeyboardLayout(serial: serial) }
            // Several layouts named by the record: one of them, else the most likely.
            let suggested =
                fitting.first { !Set(checked.record.libraryIDs).isDisjoint(with: $0.aliases.union([$0.id])) }?.id
                ?? Self.suggestion(for: checked.layout, in: fitting)
            status = .found(Found(layout: checked.layout, serial: serial, suggested: suggested))
        }
    }

    private func progressed(_ fraction: Double) {
        guard case .reading = status else { return }
        status = .reading(fraction)
    }

    private func noRecord() {
        Self.log.info("The keyboard's firmware stores no layout")
        status = .noRecord
    }

    private func fail(_ failure: PullFailure) {
        // A failure names a size, a version or a file, never the layout.
        Self.log.error("Reading the keyboard's layout failed: \(String(describing: failure), privacy: .public)")
        status = .failed(failure)
    }

    /// Decodes a record and checks it is the layout `serial` names, as this Sextant reads it.
    static func verified(_ bytes: [UInt8], serial: String) throws(PullFailure) -> Pending {
        let record: LayoutRecord
        let layout: KeyboardLayout
        do throws(LayoutRecordError) {
            record = try LayoutRecord(decoding: bytes)
            layout = try record.layout()
        } catch {
            throw .record(error)
        }
        guard let made = source(of: record, layout: layout, serial: serial) else { throw .mismatch }
        // The keyboard is recognised by the layout as this Sextant writes it. A newer Sextant's record can hold what this
        // one drops: that layout would never read as on the keyboard.
        if let fingerprint = FirmwareIdentity.sextantFingerprint(of: serial), FirmwareIdentity.fingerprint(of: layout) != fingerprint {
            throw .record(.unreadableLayout)
        }
        return Pending(record: record, layout: layout, serial: serial, source: made)
    }

    /// What put the record's layout on the keyboard: a Sextant build (`.flash`) when the record has the Sextant serial's
    /// fingerprint, or Sextant's build of an Oryx revision (`.import`, so the import rule finds it) when the layout is that
    /// revision. Nil when the record isn't what the serial names.
    static func source(of record: LayoutRecord, layout: KeyboardLayout, serial: String) -> RevisionSource? {
        if let fingerprint = FirmwareIdentity.sextantFingerprint(of: serial) {
            return String(format: "%08X", record.fingerprint) == fingerprint ? .flash : nil
        }
        return layout.oryx?.serial == serial ? .import : nil
    }

    /// The library layout a found one most likely is: the same Oryx layout, else the same title.
    static func suggestion(for layout: KeyboardLayout, in entries: [LibraryEntry]) -> UUID? {
        if let oryx = layout.oryx, let entry = entries.first(where: { $0.origin.oryxLayoutID == oryx.layoutId }) { return entry.id }
        return entries.first { $0.title == layout.title }?.id
    }

    // MARK: Adding

    /// The library layout linked to a record: the one whose id or aliases are among the record's ids, else, for an Oryx
    /// serial, the one imported from that Oryx layout. Only one it fits (``Found/fits(_:)``): an Oryx serial's import
    /// revision in a layout from elsewhere would never read as on the keyboard. Nil when several match: the user picks.
    private func linked(_ pending: Pending) -> LibraryEntry? {
        let ids = Set(pending.record.libraryIDs)
        let entries = library.entries.filter { $0.takesKeyboardLayout(serial: pending.serial) }
        let named = entries.filter { !ids.isDisjoint(with: $0.aliases.union([$0.id])) }
        if !named.isEmpty { return named.count == 1 ? named[0] : nil }
        return pending.source == .import && entries.count == 1 ? entries[0] : nil
    }

    /// The record's ids `entryID` takes as aliases: only other Macs' ids. An id of another layout here, or one already
    /// linked to another layout here, would make a build of that layout read as this one, so it is left out.
    private func aliases(from pending: Pending, for entryID: UUID) -> Set<UUID> {
        let others = library.entries.filter { $0.id != entryID }
        let taken = others.reduce(into: Set(others.map(\.id))) { $0.formUnion($1.aliases) }
        return Set(pending.record.libraryIDs).subtracting(taken).subtracting([entryID])
    }

    /// Puts the keyboard's layout in the library layout linked to it, by itself.
    private func addLinked(_ pending: Pending, to entry: LibraryEntry) async {
        do throws(LibraryError) {
            try await store.link(entry.id, to: aliases(from: pending, for: entry.id))
            let document = try await library.document(entry.id)
            // The working copy as the window has it, unsaved edits included.
            await document.flush()
            let working = document.layout
            let stored = try await store.load(entry.id)
            let added = try await addRevision(pending, to: document, stored: stored, working: working)
            await finish(added)
        } catch {
            fail(.library(error))
        }
    }

    /// Nothing more when a revision has the keyboard's layout already. Otherwise it becomes a revision, and the working
    /// copy too when that is its last flash or import: nothing newer than what was last put on a keyboard, so no work is
    /// lost (it stays in History). Edits since then stay the working copy, including any typed while this ran: `working`
    /// is the working copy `stored` was read for.
    private func addRevision(
        _ pending: Pending, to document: EditSession, stored: StoredLayout, working: KeyboardLayout
    ) async throws(LibraryError) -> Added {
        let entry = stored.entry
        let existing = await FirmwareIdentity.revision(
            runningSerial: pending.serial, of: entry.id, aliases: entry.aliases, origin: entry.origin, revisions: stored.revisions,
            library: store)
        if let existing { return Added(entryID: entry.id, revision: existing.summary, adopted: false) }
        let shipped = stored.revisions.last { $0.source == .flash || $0.source == .import }
        guard shipped?.contentHash == stored.contentHash else {
            let draft = RevisionDraft(source: pending.source, message: String(localized: "From the keyboard"), layout: pending.layout)
            let revision = try await document.recordRevision(draft)
            return Added(entryID: entry.id, revision: revision, adopted: false)
        }
        let used = try await document.useKeyboardLayout(pending.layout, source: pending.source, replacing: working)
        return Added(entryID: entry.id, revision: used.revision, adopted: used.adopted)
    }

    /// Makes a found layout a revision and the working copy of `id`, as one undoable edit in its open window.
    private func adopt(_ pending: Pending, into id: UUID) async throws(LibraryError) -> Added {
        let document = try await library.document(id)
        // Linked first: a link that fails then leaves the working copy as it was.
        try await store.link(id, to: aliases(from: pending, for: id))
        let used = try await document.useKeyboardLayout(pending.layout, source: pending.source)
        return Added(entryID: id, revision: used.revision, adopted: true)
    }

    /// Adds a found layout as a new library layout, kept exactly (title included): any change would change its fingerprint,
    /// and then it wouldn't read as on the keyboard.
    private func create(_ pending: Pending) async throws(LibraryError) -> Added {
        let layout = pending.layout
        let origin: LayoutOrigin = layout.oryx.map { .oryx(layoutId: $0.layoutId, revisionId: $0.revisionId) } ?? .local
        let first = RevisionDraft(source: pending.source, message: String(localized: "From the keyboard"), layout: layout)
        let entry = try await store.create(layout, origin: origin, firstRevision: first)
        try await store.link(entry.id, to: aliases(from: pending, for: entry.id))
        let revision = try await store.load(entry.id).revisions.last
        return Added(entryID: entry.id, revision: revision, adopted: true)
    }

    private func finish(_ added: Added) async {
        pending = nil
        await library.refresh()
        onKeyboard.refresh()
        status = .added(added)
        Self.log.info("Put the keyboard's layout in \(added.entryID, privacy: .public), adopted: \(added.adopted, privacy: .public)")
    }
}

extension LayoutOrigin {
    /// The Oryx layout an Oryx origin names.
    fileprivate var oryxLayoutID: String? {
        if case let .oryx(layoutId, _) = self { layoutId } else { nil }
    }
}

extension LibraryEntry {
    /// Whether the keyboard's layout, read for `serial`, can become a revision of this layout. An Oryx serial reads as on
    /// the keyboard only in a layout from that Oryx layout, however linked (the import rule, ADR 0039); a Sextant serial
    /// reads as on the keyboard in any layout linked to the record's ids, which adding it does.
    fileprivate func takesKeyboardLayout(serial: String) -> Bool {
        FirmwareIdentity.sextantFingerprint(of: serial) != nil || isOnKeyboard(serial: serial)
    }
}
