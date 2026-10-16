import Clocks
import Foundation
import SextantDomain
import Testing

@testable import SextantApplication

@MainActor
struct OnKeyboardTests {
    /// Oryx's `KlgM7/40xJ7M`.
    let layout: KeyboardLayout
    let store = InMemoryLibrary()
    let watcher = FakeDeviceWatcher()
    let clock = TestClock()
    let live: LiveSession
    let library: Library
    let onKeyboard: OnKeyboard

    init() throws {
        layout = try KeyboardLayout(oryxJSON: Fixtures.userLayoutData)
        live = LiveSession(watcher: watcher, link: FakeKeyboardLink(), clock: TestClock()) { false }
        library = Library(store: store)
        onKeyboard = OnKeyboard(library: library, store: store, live: live)
    }

    func retitled(_ layout: KeyboardLayout, _ title: String) -> KeyboardLayout {
        var layout = layout
        layout.title = title
        return layout
    }

    func resolve(_ serial: String?) async -> OnKeyboard.Running? {
        await OnKeyboard.resolve(serial, entries: await store.entries(), store: store)
    }

    /// Runs the real Build & Flash of `document` until it records the flash. `whileVerifying` runs once the image is
    /// written, before the keyboard comes back.
    func flash(_ document: EditSession, whileVerifying: () async -> Void = {}) async throws -> RevisionSummary? {
        let generator = FakeGenerator()
        let session = BuildFlashSession(
            session: document, library: store, generator: generator, toolchain: FakeToolchain(), watcher: watcher,
            flasher: FakeFlasher(), md5: { _ in "d41d8cd9" }, clock: clock, issues: { _ in [] }, live: live)
        session.buildAndFlash(connectedKeyboard: nil)
        #expect(await eventually { session.phase == .waitingForFlashMode(stillWaiting: false) && watcher.subscriberCount == 2 })
        watcher.attach(.bootloader(.stm32()))
        #expect(
            await eventually {
                await clock.advance(by: .milliseconds(100))
                return session.phase == .verifying
            })
        await whileVerifying()
        let serial = try #require(generator.lastIdentity?.serial)
        watcher.detach(9)
        watcher.attach(.keyboard(.voyager(id: 2, serial: serial)))
        #expect(await eventually { if case .done = session.phase { true } else { false } })
        guard case let .done(revision, nil) = session.phase else {
            Issue.record("\(session.phase)")
            return nil
        }
        return revision
    }

    @Test func anOryxSerialNamesItsImportRevision() async throws {
        let entry = try await store.create(
            layout, origin: .oryx(layoutId: "KlgM7", revisionId: "40xJ7M"), firstRevision: RevisionDraft(source: .import, layout: layout))
        try await store.save(retitled(layout, "Edited"), to: entry.id)
        let running = await resolve("KlgM7/40xJ7M")
        #expect(running?.entry.id == entry.id && running?.revision?.source == .import)
        #expect(running?.layout == layout, "not the edits made since")
    }

    @Test func aSextantSerialNamesWhatWasFlashedEvenAfterLaterEdits() async throws {
        let entry = try await store.create(layout, origin: .local, firstRevision: RevisionDraft(source: .save, layout: layout))
        let flashed = retitled(layout, "Flashed")
        let serial = FirmwareIdentity(layout: flashed, libraryID: entry.id, importedLayout: nil).serial
        try await store.save(flashed, to: entry.id)
        var running = await resolve(serial)
        #expect(
            running?.entry.id == entry.id && running?.revision == nil && running?.layout == flashed, "the working copy, not recorded yet")

        let revision = try await store.appendRevision(RevisionDraft(source: .flash, layout: flashed), to: entry.id)
        running = await resolve(serial)
        #expect(running?.revision?.id == revision.id && running?.layout == flashed, "the working copy")

        try await store.save(retitled(layout, "Edited since"), to: entry.id)
        running = await resolve(serial)
        #expect(running?.entry.id == entry.id && running?.revision?.id == revision.id && running?.layout == flashed, "the flash revision")
    }

    /// The keyboard runs the user's other Mac's build: once linked (ADR 0061), the same content here is what it runs.
    @Test func aLinkedLayoutsBuildFromAnotherMacResolves() async throws {
        let entry = try await store.create(layout, origin: .local, firstRevision: RevisionDraft(source: .save, layout: layout))
        let otherMac = UUID()
        let flashed = retitled(layout, "Flashed")
        let serial = FirmwareIdentity(layout: flashed, libraryID: otherMac, importedLayout: nil).serial
        try await store.save(flashed, to: entry.id)
        #expect(await resolve(serial) == nil, "not linked")

        try await store.link(entry.id, to: [otherMac])
        var running = await resolve(serial)
        #expect(running?.entry.id == entry.id && running?.revision == nil && running?.layout == flashed, "the working copy has it")
        let revision = try await store.appendRevision(RevisionDraft(source: .flash, layout: flashed), to: entry.id)
        try await store.save(retitled(layout, "Edited since"), to: entry.id)
        running = await resolve(serial)
        #expect(running?.revision?.id == revision.id && running?.layout == flashed, "the flash revision with its content")
    }

    /// A revision added to a layout doesn't change the library's entries: ``OnKeyboard/refresh()`` looks again.
    @Test func refreshResolvesAgainAndTheResolvedSerialFollowsTheKeyboard() async throws {
        let entry = try await store.create(layout, origin: .local, firstRevision: RevisionDraft(source: .save, layout: layout))
        await library.refresh()
        let flashed = retitled(layout, "Flashed")
        let serial = FirmwareIdentity(layout: flashed, libraryID: entry.id, importedLayout: nil).serial
        live.start()
        onKeyboard.start()
        watcher.attach(.keyboard(.voyager(serial: serial)))
        #expect(await eventually { onKeyboard.resolvedSerial == serial })
        #expect(onKeyboard.running == nil, "looked up, and the library has no revision with it")

        _ = try await store.appendRevision(RevisionDraft(source: .flash, layout: flashed), to: entry.id)
        onKeyboard.refresh()
        #expect(await eventually { onKeyboard.running?.layout == flashed })
        watcher.detach(1)
        #expect(await eventually { onKeyboard.resolvedSerial == nil && onKeyboard.running == nil }, "unplugged")
    }

    @Test func anythingElseIsNil() async throws {
        let entry = try await store.create(
            layout, origin: .oryx(layoutId: "KlgM7", revisionId: "40xJ7M"), firstRevision: RevisionDraft(source: .import, layout: layout))
        #expect(await resolve(nil) == nil, "no keyboard")
        #expect(await resolve("KlgM7/zzzzzz") == nil, "an Oryx revision never imported")
        #expect(await resolve("Q9x2/aa11") == nil, "another layout")
        #expect(await resolve("sx-\(entry.id.uuidString.prefix(8))-00000000") == nil, "a build the library has no revision of")
    }

    @Test func followsTheSerialAndLibraryRefreshes() async throws {
        await library.refresh()
        live.start()
        onKeyboard.start()
        watcher.attach(.keyboard(.voyager(serial: "KlgM7/40xJ7M")))
        #expect(await eventually { live.firmwareSerial == "KlgM7/40xJ7M" })
        try await library.add(imported: layout)
        #expect(await eventually { onKeyboard.running?.revision?.source == .import }, "importing what the keyboard runs")
        watcher.detach(1)
        #expect(await eventually { onKeyboard.running == nil }, "unplugged")
    }

    /// Build & Flash records its revision before it lets go of flash mode; the release is what makes OnKeyboard look again.
    @Test func aFlashEndsOnItsRecordedRevision() async throws {
        let entry = try await library.importOryxJSON(Fixtures.userLayoutData)
        let document = try await library.open(entry.id, autosaveDelay: .milliseconds(1))
        live.start()
        onKeyboard.start()
        await store.beforeAppend { try? await Task.sleep(for: .milliseconds(30)) }  // as long as a disk write
        document.setCode("KC_F13", layer: 0, index: 1)
        let built = document.layout
        let revision = try #require(
            try await flash(document) {
                // The document moves on while it flashes, so only the recorded revision can name what was flashed.
                document.setCode("KC_F14", layer: 0, index: 1)
                await document.flush()
            })
        #expect(await eventually { onKeyboard.running?.revision?.id == revision.id && onKeyboard.running?.layout == built })
    }

    /// The same Oryx layout imported twice claims one serial: the copy Sextant flashed wins over a newer twin.
    @Test func theEntrySextantFlashedWinsOverATwin() async throws {
        let flashed = try await library.importOryxJSON(Fixtures.userLayoutData)
        let twin = try await library.importOryxJSON(Fixtures.userLayoutData)
        #expect(library.entries.first?.id == twin.id, "the twin is newer")
        let document = try await library.open(flashed.id, autosaveDelay: .milliseconds(1))
        live.start()
        onKeyboard.start()
        _ = try await flash(document)
        #expect(live.firmwareSerial == "KlgM7/40xJ7M")
        #expect(await eventually { onKeyboard.running?.entry.id == flashed.id })
    }
}
