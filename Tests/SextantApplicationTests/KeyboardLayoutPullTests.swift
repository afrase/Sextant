import Foundation
import SextantDomain
import Testing

@testable import SextantApplication

/// Reading the layout back from the keyboard (ADR 0061): the user's other Mac flashed a Sextant build that stores its
/// layout, and this Mac, whose library doesn't have that version, reads it over Live View and puts it in the library.
@MainActor
struct KeyboardLayoutPullTests {
    let store = InMemoryLibrary()
    let watcher = FakeDeviceWatcher()
    let link = FakeKeyboardLink()
    let live: LiveSession
    let library: Library
    let onKeyboard: OnKeyboard
    let pull: KeyboardLayoutPull
    /// The layout's library id on the other Mac.
    let otherMac = UUID()
    /// What the other Mac flashed: a small layout, so a read takes few reports.
    let flashed: KeyboardLayout
    /// An earlier version of it.
    let older: KeyboardLayout

    init() {
        // A real clock: each part of the record is waited for as the firmware would answer it.
        live = LiveSession(watcher: watcher, link: link, clock: ContinuousClock()) { false }
        library = Library(store: store)
        onKeyboard = OnKeyboard(library: library, store: store, live: live)
        pull = KeyboardLayoutPull(live: live, onKeyboard: onKeyboard, library: library, store: store)
        var layout = KeyboardLayout.blankQWERTY(title: "Travel")
        layout.updateKey(layer: 0, index: 1) { $0 = Key("KC_F13") }
        flashed = layout
        layout.updateKey(layer: 0, index: 1) { $0 = Key("KC_F14") }
        older = layout
    }

    /// The serial a Sextant build of `layout` reports when the Mac whose library id is `id` built it.
    func serial(of layout: KeyboardLayout, from id: UUID) -> String {
        FirmwareIdentity(layout: layout, libraryID: id, importedLayout: nil).serial
    }

    /// The keyboard's firmware stores `layout` with `ids` (the other Mac's alone unless given).
    func storeRecord(of layout: KeyboardLayout, ids: [UUID]? = nil) throws {
        link.storeLayoutRecord(try LayoutRecord(layout: layout, libraryIDs: ids ?? [otherMac]).encoded())
    }

    /// Starts everything, then plugs in a keyboard reporting `serial` and pairs Live View with it.
    func connect(_ serial: String) async {
        await library.refresh()
        live.start()
        onKeyboard.start()
        pull.start()
        live.startLive()
        watcher.attach(.keyboard(.voyager(serial: serial)))
        #expect(await pair(session: 0))
    }

    /// Waits for link session `n` (counting from 0) to open, then pairs it: its first layer report is live mode.
    func pair(session n: Int) async -> Bool {
        guard await eventually({ link.sessionCount == n + 1 }) else { return false }
        link.send(.layer(0))
        return await eventually { live.canSend }
    }

    /// Waits up to about 5 s for `condition`: a read takes a report for every 24 bytes of the record.
    func settles(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<1000 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    /// Reads begun: each asks for the record's first part.
    var reads: Int { link.commands.joined().filter { $0 == .readLayoutRecord(offset: 0) }.count }
    var found: KeyboardLayoutPull.Found? { if case let .found(found) = pull.status { found } else { nil } }
    var added: KeyboardLayoutPull.Added? { if case let .added(added) = pull.status { added } else { nil } }

    // MARK: Reading by itself

    @Test func readsByItselfWhenTheLibraryLacksWhatTheKeyboardRuns() async throws {
        let sameName = try await store.create(older, origin: .local, firstRevision: RevisionDraft(source: .save, layout: older))
        try storeRecord(of: flashed)
        let running = serial(of: flashed, from: otherMac)
        await connect(running)
        #expect(await settles { found != nil })
        #expect(found?.layout == flashed && found?.serial == running)
        #expect(found?.suggested == sameName.id, "the same title")
        #expect(reads == 1)
        #expect(onKeyboard.running == nil, "nothing is added until the user chooses where")
        #expect(try await store.load(sameName.id).revisions.count == 1)
    }

    @Test func aLayoutTheLibraryHasIsntRead() async throws {
        let entry = try await store.create(flashed, origin: .local, firstRevision: RevisionDraft(source: .flash, layout: flashed))
        try storeRecord(of: flashed, ids: [entry.id])
        await connect(serial(of: flashed, from: entry.id))
        #expect(await eventually { onKeyboard.running?.entry.id == entry.id })
        try await Task.sleep(for: .milliseconds(50))
        #expect(reads == 0 && pull.status == .idle)
    }

    @Test func firmwareWithoutARecordIsReadOncePerConnection() async throws {
        // Nothing stored: the firmware answers "unknown command", as Oryx's builds do.
        let running = serial(of: flashed, from: otherMac)
        await connect(running)
        #expect(await settles { pull.status == .noRecord })
        #expect(reads == 1)

        // Live View off and on again: the same connection.
        live.stopLive()
        #expect(await eventually { !live.canSend })
        live.startLive()
        #expect(await pair(session: 1))
        try await Task.sleep(for: .milliseconds(50))
        #expect(reads == 1 && pull.status == .noRecord)

        // Plugged in again: read again.
        watcher.detach(1)
        #expect(await eventually { live.connection == .noKeyboard })
        try await Task.sleep(for: .milliseconds(20))
        watcher.attach(.keyboard(.voyager(serial: running)))
        #expect(await pair(session: 2))
        #expect(await settles { reads == 2 && pull.status == .noRecord })
    }

    @Test func aRecordThatIsntWhatTheSerialNamesIsRefused() async throws {
        try storeRecord(of: flashed)
        await connect("sx-\(otherMac.uuidString.prefix(8))-00000000")
        #expect(await settles { pull.status == .failed(.mismatch) })
        #expect(await store.entries().isEmpty)
    }

    @Test func theRecordMustBeWhatTheSerialNames() {
        let record = LayoutRecord(layout: flashed, libraryIDs: [otherMac])
        #expect(KeyboardLayoutPull.source(of: record, layout: flashed, serial: serial(of: flashed, from: otherMac)) == .flash)
        #expect(KeyboardLayoutPull.source(of: record, layout: flashed, serial: serial(of: flashed, from: UUID())) == .flash)
        #expect(KeyboardLayoutPull.source(of: record, layout: flashed, serial: serial(of: older, from: otherMac)) == nil)
        #expect(KeyboardLayoutPull.source(of: record, layout: flashed, serial: "Q9x2/aa11") == nil)
        var oryx = flashed
        oryx.oryx = OryxRevisionInfo(layoutId: "Q9x2", revisionId: "aa11")
        let oryxRecord = LayoutRecord(layout: oryx, libraryIDs: [otherMac])
        #expect(KeyboardLayoutPull.source(of: oryxRecord, layout: oryx, serial: "Q9x2/aa11") == .import, "Sextant's build of it")
        #expect(KeyboardLayoutPull.source(of: oryxRecord, layout: oryx, serial: "Q9x2/bb22") == nil)
        do throws(PullFailure) {
            _ = try KeyboardLayoutPull.verified([0x00, 0x01, 0x02], serial: serial(of: flashed, from: otherMac))
            Issue.record("junk read as a record")
        } catch {
            #expect(error == .record(.malformed))
        }
    }

    // MARK: A linked layout

    /// The other Mac's record names this Mac's id (linked there): its layout is added by itself, and the keyboard reads
    /// as running it.
    @Test func aLinkedLayoutGetsTheKeyboardsVersionByItself() async throws {
        let entry = try await store.create(older, origin: .local, firstRevision: RevisionDraft(source: .flash, layout: older))
        try storeRecord(of: flashed, ids: [otherMac, entry.id])
        await connect(serial(of: flashed, from: otherMac))
        #expect(await settles { added != nil })
        let result = try #require(added)
        #expect(result.entryID == entry.id && result.adopted, "nothing newer than the last flash: the keyboard's replaces it")
        #expect(result.revision?.source == .flash && result.revision?.message == "From the keyboard")
        let stored = try await store.load(entry.id)
        #expect(stored.layout == flashed && stored.revisions.count == 2)
        #expect(stored.entry.aliases == [otherMac])
        #expect(await eventually { onKeyboard.running?.entry.id == entry.id && onKeyboard.running?.revision?.id == result.revision?.id })
        #expect(reads == 1)
    }

    /// Edits since the last flash are newer than anything on a keyboard: they stay the working copy, and History gets the
    /// keyboard's version, in the open window too.
    @Test func editsSinceTheLastFlashStayTheWorkingCopy() async throws {
        let entry = try await store.create(older, origin: .local, firstRevision: RevisionDraft(source: .flash, layout: older))
        await library.refresh()
        let document = try await library.open(entry.id, autosaveDelay: .milliseconds(1))
        document.setTitle("Travel, edited")
        let edited = document.layout
        try storeRecord(of: flashed, ids: [otherMac])
        try await store.link(entry.id, to: [otherMac])
        await connect(serial(of: flashed, from: otherMac))
        #expect(await settles { added != nil })
        let result = try #require(added)
        #expect(result.entryID == entry.id && !result.adopted)
        #expect(document.layout == edited && document.isEditedSinceRevision, "the edits stay")
        #expect(document.revisions.last == result.revision, "the window's History lists it")
        let revisionID = try #require(result.revision?.id)
        #expect(try await store.layout(ofRevision: revisionID, in: entry.id) == flashed)
        #expect(await eventually { onKeyboard.running?.revision?.id == result.revision?.id && onKeyboard.running?.layout == flashed })
    }

    @Test func adoptingInAnOpenWindowIsOneUndoStep() async throws {
        let entry = try await store.create(older, origin: .local, firstRevision: RevisionDraft(source: .flash, layout: older))
        await library.refresh()
        let document = try await library.open(entry.id, autosaveDelay: .milliseconds(1))
        let undo = UndoManager()
        undo.groupsByEvent = false
        document.undoManager = undo
        try storeRecord(of: flashed, ids: [otherMac, entry.id])
        undo.beginUndoGrouping()
        await connect(serial(of: flashed, from: otherMac))
        #expect(await settles { added != nil })
        undo.endUndoGrouping()
        #expect(added?.adopted == true && document.layout == flashed)
        #expect(undo.undoActionName == "Use the Keyboard's Layout")
        undo.undo()
        #expect(document.layout == older)
        #expect(document.revisions.count == 2, "undo leaves the revision, as after an import")
    }

    /// Sextant's build of an Oryx revision reports Oryx's serial: an import of that Oryx layout is linked, and the record
    /// becomes that Oryx revision's import, which the keyboard then reads as running.
    @Test func sextantsBuildOfAnOryxRevisionBecomesItsImport() async throws {
        var imported = flashed
        imported.oryx = OryxRevisionInfo(layoutId: "Q9x2", revisionId: "zz00")
        var newer = flashed
        newer.oryx = OryxRevisionInfo(layoutId: "Q9x2", revisionId: "aa11")
        let entry = try await store.create(
            imported, origin: .oryx(layoutId: "Q9x2", revisionId: "zz00"), firstRevision: RevisionDraft(source: .import, layout: imported))
        try storeRecord(of: newer)
        await connect("Q9x2/aa11")
        #expect(await settles { added != nil })
        let result = try #require(added)
        #expect(result.entryID == entry.id && result.adopted && result.revision?.source == .import)
        #expect(try await store.load(entry.id).entry.origin == .oryx(layoutId: "Q9x2", revisionId: "aa11"))
        #expect(await eventually { onKeyboard.running?.revision?.id == result.revision?.id })
    }

    // MARK: A found layout

    @Test func aFoundLayoutCanBeANewLayout() async throws {
        try storeRecord(of: flashed)
        await connect(serial(of: flashed, from: otherMac))
        #expect(await settles { found != nil })
        await pull.add(to: nil)
        let result = try #require(added)
        #expect(result.adopted)
        let stored = try await store.load(result.entryID)
        #expect(stored.layout == flashed && stored.entry.title == "Travel" && stored.entry.origin == .local, "kept exactly")
        #expect(stored.entry.aliases == [otherMac])
        #expect(stored.revisions.map(\.message) == ["From the keyboard"] && stored.revisions.last == result.revision)
        #expect(library.entries.map(\.id) == [result.entryID])
        #expect(await eventually { onKeyboard.running?.entry.id == result.entryID })
    }

    @Test func aFoundLayoutCanBecomeALayoutsWorkingCopy() async throws {
        let entry = try await store.create(older, origin: .local, firstRevision: RevisionDraft(source: .save, layout: older))
        var edited = older
        edited.title = "Mine"
        try await store.save(edited, to: entry.id)
        try storeRecord(of: flashed)
        await connect(serial(of: flashed, from: otherMac))
        #expect(await settles { found != nil })
        await pull.add(to: entry.id)
        let result = try #require(added)
        #expect(result.entryID == entry.id && result.adopted)
        let stored = try await store.load(entry.id)
        #expect(stored.layout == flashed, "the keyboard's layout, title included")
        #expect(stored.revisions.map(\.message) == [nil, "Before using the keyboard's layout", "From the keyboard"])
        #expect(try await store.layout(ofRevision: stored.revisions[1].id, in: entry.id) == edited, "the edits stay in History")
        #expect(stored.entry.aliases == [otherMac])
        #expect(await eventually { onKeyboard.running?.entry.id == entry.id })
    }

    @Test func getLayoutTurnsLiveViewOnFirst() async throws {
        await library.refresh()
        live.start()
        onKeyboard.start()
        try storeRecord(of: flashed)
        watcher.attach(.keyboard(.voyager(serial: serial(of: flashed, from: otherMac))))
        #expect(await eventually { if case .liveOff = live.connection { true } else { false } })
        let reading = Task { await pull.read(startingLiveView: true) }
        #expect(await pair(session: 0))
        await reading.value
        #expect(live.isLive && found?.layout == flashed)
    }

    @Test func aDismissedLayoutIsntReadByItselfAgainUntilTheSerialChanges() async throws {
        try storeRecord(of: flashed)
        let running = serial(of: flashed, from: otherMac)
        await connect(running)
        #expect(await settles { found != nil })
        pull.dismiss()
        #expect(pull.status == .idle)

        watcher.detach(1)
        #expect(await eventually { live.connection == .noKeyboard })
        try await Task.sleep(for: .milliseconds(20))
        watcher.attach(.keyboard(.voyager(serial: running)))
        #expect(await pair(session: 1))
        try await Task.sleep(for: .milliseconds(50))
        #expect(reads == 1 && pull.status == .idle, "dismissed")
        await pull.read()
        #expect(found?.layout == flashed && reads == 2, "Get Layout always reads")
    }
}
