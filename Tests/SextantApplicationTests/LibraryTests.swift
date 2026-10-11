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
