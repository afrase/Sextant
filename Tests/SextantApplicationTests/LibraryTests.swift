import Foundation
import SextantDomain
import Testing

@testable import SextantApplication

@MainActor
struct LibraryTests {
    @Test func importStripsForkAndRecordsARevision() async throws {
        let store = InMemoryLibrary()
        let library = Library(store: store)
        let entry = try await library.importOryxJSON(Fixtures.userLayoutData)
        #expect(entry.title == "My MacOS Layout")
        #expect(entry.origin == .oryx(layoutId: "KlgM7", revisionId: "40xJ7M"))
        #expect(library.entries.map(\.id) == [entry.id])
        let stored = try await store.load(entry.id)
        #expect(stored.revisions.map(\.source) == [.import])
    }

    @Test func importRefusesJunk() async {
        let library = Library(store: InMemoryLibrary())
        await #expect(throws: LibraryError.self) { try await library.importOryxJSON(Data("nope".utf8)) }
    }

    @Test func cleansTitles() {
        #expect(Library.cleanImportedTitle("My MacOS Layout [fork]") == "My MacOS Layout")
        #expect(Library.cleanImportedTitle("  Plain  ") == "Plain")
    }

    /// Closing a window and quitting write the pending edit, and close frees the layout for another window.
    @Test func closingAndQuittingWritePendingEdits() async throws {
        let store = InMemoryLibrary()
        let library = Library(store: store)
        let entry = try await library.importOryxJSON(Fixtures.userLayoutData)
        let session = try await library.open(entry.id, autosaveDelay: .seconds(60))
        #expect(library.isOpen(entry.id))
        session.select(key: 1)
        session.setCode("KC_F1")
        await library.flushOpenSessions()
        #expect(try await store.load(entry.id).layout.key(layer: 0, index: 1)?.tap?.code == "KC_F1")
        session.setCode("KC_F2")
        await library.close(session)
        #expect(!library.isOpen(entry.id))
        #expect(try await store.load(entry.id).layout.key(layer: 0, index: 1)?.tap?.code == "KC_F2")
    }

    /// A document whose window went away still holds its last edit until its autosave: reopening writes it first.
    @Test func reopeningWritesTheLastDocumentsPendingEditFirst() async throws {
        let library = Library(store: InMemoryLibrary())
        let entry = try await library.importOryxJSON(Fixtures.userLayoutData)
        var session: EditSession? = try await library.open(entry.id, autosaveDelay: .seconds(60))
        session?.select(key: 1)
        session?.setCode("KC_F3")
        session = nil  // its pending save keeps it alive
        #expect(library.isOpen(entry.id))
        let reopened = try await library.open(entry.id)
        #expect(reopened.layout.key(layer: 0, index: 1)?.tap?.code == "KC_F3")
    }

    @Test func managesLayouts() async throws {
        let library = Library(store: InMemoryLibrary())
        let entry = try await library.importOryxJSON(Fixtures.userLayoutData)
        await library.rename(entry.id, to: "Work")
        #expect(library.entries.first?.title == "Work")
        let copy = await library.duplicate(entry.id)
        #expect(library.entries.count == 2 && copy != nil)
        await library.trash(entry.id)
        #expect(library.entries.map(\.id) == [copy?.id])
        await library.trash(entry.id)
        #expect(library.lastError == .notFound(entry.id))
    }
}
