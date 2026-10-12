import Foundation
import SextantApplication
import SextantDomain
import Testing

/// Save Revision, Restore and recorded flashes (ADR 0043).
@MainActor
struct EditSessionHistoryTests {
    let store = InMemoryLibrary()

    func open() async throws -> (EditSession, UndoManager) {
        let library = Library(store: store)
        let entry = try await library.importOryxJSON(Fixtures.userLayoutData)
        let session = try await library.open(entry.id, autosaveDelay: .milliseconds(1))
        let undo = UndoManager()
        undo.groupsByEvent = false
        session.undoManager = undo
        return (session, undo)
    }

    func step(_ undo: UndoManager, _ body: () -> Void) {
        undo.beginUndoGrouping()
        body()
        undo.endUndoGrouping()
    }

    @Test func savingMovesTheBaseline() async throws {
        let (session, undo) = try await open()
        step(undo) { session.setCode("KC_Q", layer: 0, index: 1) }
        #expect(session.isEditedSinceRevision)
        let saved = try await session.saveRevision(source: .save, message: "Edited 1 key on Main")
        #expect(!session.isEditedSinceRevision)
        #expect(session.revisions.last == saved && saved.message == "Edited 1 key on Main")
        #expect(try await session.revisionLayout(saved.id) == session.layout)
    }

    @Test func restoreCheckpointsUnsavedEditsKeepsTheTitleAndIsOneUndoStep() async throws {
        let (session, undo) = try await open()
        let imported = try #require(session.revisions.first)
        let original = session.layout
        step(undo) { session.setCode("KC_Q", layer: 0, index: 1) }
        try await session.saveRevision(source: .save, message: nil)
        step(undo) { session.setCode("KC_W", layer: 0, index: 2) }
        step(undo) { session.setTitle("Work") }
        let edited = session.layout

        undo.beginUndoGrouping()
        try await session.restoreRevision(imported)
        undo.endUndoGrouping()

        var expected = original
        expected.title = "Work"
        #expect(session.layout == expected, "the revision, under the current title")
        #expect(session.revisions.map(\.source) == [.import, .save, .save, .save])
        #expect(session.revisions.last?.message == "Restored revision 1")
        #expect(try await session.revisionLayout(session.revisions[2].id) == edited, "unsaved edits are checkpointed first")
        #expect(!session.isEditedSinceRevision)
        #expect(undo.undoActionName == "Restore Revision")
        undo.undo()
        #expect(session.layout == edited, "one step undoes the restore")
        #expect(session.revisions.count == 4, "revisions are append-only")
    }

    @Test func aFailedRestoreLeavesTheDocument() async throws {
        let (session, undo) = try await open()
        let imported = try #require(session.revisions.first)
        // Unsaved edits can't be checkpointed from a stale copy.
        await store.failSaves(with: .io("disk full"))
        step(undo) { session.setCode("KC_Q", layer: 0, index: 1) }
        let edited = session.layout

        let missing = RevisionSummary(id: "missing", number: 9, createdAt: .now, source: .save, message: nil, contentHash: "")
        await #expect(throws: LibraryError.notFound(session.id)) { try await session.restoreRevision(missing) }
        await #expect(throws: LibraryError.io("disk full")) { try await session.restoreRevision(imported) }
        #expect(session.layout == edited && session.revisions.count == 1)
        #expect(undo.undoActionName == "Set Tap", "the edit is still the last step")
    }

    @Test func restoringWhatTheDocumentIsAddsNothing() async throws {
        let (session, _) = try await open()
        try await session.restoreRevision(try #require(session.revisions.first))
        #expect(session.revisions.count == 1)
    }

    /// A flash of a build older than the document is recorded and becomes the baseline: the document stays edited, and
    /// undoing back to the build clears "Edited", as the library sees it too.
    @Test func recordRevisionMovesTheBaselineToWhatItRecords() async throws {
        let (session, undo) = try await open()
        step(undo) { session.setCode("KC_Q", layer: 0, index: 1) }
        let built = session.layout
        step(undo) { session.setCode("KC_W", layer: 0, index: 2) }
        let recorded = try await session.recordRevision(RevisionDraft(source: .flash, message: "Flashed", layout: built))
        #expect(session.revisions.last == recorded)
        #expect(try await session.revisionLayout(recorded.id) == built)
        #expect(session.isEditedSinceRevision)

        undo.undo()
        await session.flush()
        #expect(!session.isEditedSinceRevision)
        #expect(try await store.load(session.id).hasEditsSinceLastRevision == false)
        undo.undo()
        await session.flush()
        #expect(session.isEditedSinceRevision)
        #expect(try await store.load(session.id).hasEditsSinceLastRevision)
    }
}
