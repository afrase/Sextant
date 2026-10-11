import SextantApplication
import SextantDomain
import Testing

/// The window compares the keyboard's serial against the same import a build does (ADR 0019).
@MainActor
struct ImportedLayoutTests {
    @Test func buildFlashHandsOutTheLatestImport() async throws {
        let store = InMemoryLibrary()
        let library = Library(store: store)
        let entry = try await library.importOryxJSON(Fixtures.userLayoutData)
        let document = try await library.open(entry.id)
        let session = BuildFlashSession(
            session: document, library: store, generator: FakeGenerator(), toolchain: FakeToolchain(), watcher: FakeDeviceWatcher(),
            flasher: FakeFlasher(), md5: { _ in "" })
        let imported = try #require(await session.importedLayout())
        #expect(imported == document.layout)
        #expect(FirmwareIdentity(layout: document.layout, libraryID: entry.id, importedLayout: imported).serial == "KlgM7/40xJ7M")
    }
}
