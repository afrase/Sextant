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
        let revision = try await store.appendRevision(RevisionDraft(source: .flash, layout: flashed), to: entry.id)
        let serial = FirmwareIdentity(layout: flashed, libraryID: entry.id, importedLayout: nil).serial
        try await store.save(flashed, to: entry.id)
        var running = await resolve(serial)
        #expect(running?.entry.id == entry.id && running?.revision == revision && running?.layout == flashed, "the working copy")

        try await store.save(retitled(layout, "Edited since"), to: entry.id)
        running = await resolve(serial)
        #expect(running?.entry.id == entry.id && running?.revision == revision && running?.layout == flashed, "the flash revision")
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

    @Test func aFlashShowsOnceItsRevisionIsRecorded() async throws {
        live.start()
        onKeyboard.start()
        let entry = try await store.create(layout, origin: .local, firstRevision: RevisionDraft(source: .save, layout: layout))
        await library.refresh()
        let owner = NSObject()
        #expect(live.claimFlashMode(for: entry.id, owner: owner))
        // The keyboard comes back running the build before Build & Flash records it; the document has moved on.
        let flashed = retitled(layout, "Flashed")
        let serial = FirmwareIdentity(layout: flashed, libraryID: entry.id, importedLayout: nil).serial
        watcher.attach(.keyboard(.voyager(serial: serial)))
        #expect(await eventually { live.firmwareSerial == serial })
        try await Task.sleep(for: .milliseconds(50))
        #expect(onKeyboard.running == nil)

        let revision = try await store.appendRevision(RevisionDraft(source: .flash, layout: flashed), to: entry.id)
        live.releaseFlashMode(owner: owner)
        #expect(await eventually { onKeyboard.running?.revision == revision && onKeyboard.running?.layout == flashed })
    }
}
