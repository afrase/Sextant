import Foundation
import SextantApplication
import SextantDomain
import Testing

/// New Layout, and renaming or duplicating a layout while a window has it open (spec §3.6, §12.1).
@MainActor
struct LibraryManagementTests {
    let store = InMemoryLibrary()

    @Test func newLayoutStartsUnedited() async throws {
        let library = Library(store: store)
        #expect(!library.hasLoaded)
        await library.refresh()
        #expect(library.hasLoaded && library.entries.isEmpty, "an empty library, not one still loading")
        let entry = try #require(await library.create(.blankQWERTY(title: "Untitled Layout")))
        #expect(entry.origin == .local && library.entries.map(\.id) == [entry.id])
        let session = try await library.open(entry.id)
        #expect(session.revisions.count == 1 && !session.isEditedSinceRevision)
    }

    /// The open document renames itself (undoably, through `setTitle`), so its next autosave can't put the old title back.
    @Test func renamingAnOpenLayoutGoesThroughItsDocument() async throws {
        let library = Library(store: store)
        let entry = try await library.importOryxJSON(Fixtures.userLayoutData)
        let session = try await library.open(entry.id, autosaveDelay: .seconds(60))
        await library.rename(entry.id, to: "  Work  ")
        #expect(session.layout.title == "Work" && library.entries.first?.title == "Work")
        session.select(key: 1)
        session.setCode("KC_F1")
        await session.flush()
        #expect(await store.layout(entry.id)?.title == "Work", "a later autosave keeps the new title")
    }

    @Test func duplicatingAnOpenLayoutKeepsItsLastEdit() async throws {
        let library = Library(store: store)
        let entry = try await library.importOryxJSON(Fixtures.userLayoutData)
        let session = try await library.open(entry.id, autosaveDelay: .seconds(60))
        session.select(key: 1)
        session.setCode("KC_F2")
        let copy = try #require(await library.duplicate(entry.id))
        #expect(await store.layout(copy.id)?.key(layer: 0, index: 1)?.tap?.code == "KC_F2")
    }

    /// One undo step per change; Navigator settings go to the Navigator; ids outside the catalog are ignored.
    @Test func settingsAreOneUndoStepEach() async throws {
        let library = Library(store: store)
        let entry = try await library.importOryxJSON(try Fixtures.data("my-layout-KlgM7-full.json"))
        let session = try await library.open(entry.id, autosaveDelay: .seconds(60))
        let undo = UndoManager()
        undo.groupsByEvent = false
        session.undoManager = undo
        undo.beginUndoGrouping()
        session.setSetting("automouseTime", to: .number(800))
        undo.endUndoGrouping()
        #expect(session.layout.navigator?.options["automouseTime"] == .number(800))
        #expect(undo.undoActionName == "Change Setting")
        let before = session.layout
        session.setSetting("notASetting", to: .bool(true))
        #expect(session.layout == before)
        undo.undo()
        #expect(session.layout.navigator?.options["automouseTime"] == nil)
    }
}
