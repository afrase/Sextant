import Foundation
import SextantApplication
import SextantDomain
import Testing

/// Never lose work: every change reaches a recovery copy until the library has it.
@MainActor
struct RecoveryTests {
    let store = InMemoryLibrary()

    func open(autosaveDelay: Duration = .milliseconds(1)) async throws -> EditSession {
        let library = Library(store: store)
        let entry = try await library.importOryxJSON(Fixtures.userLayoutData)
        return try await library.open(entry.id, autosaveDelay: autosaveDelay)
    }

    @Test func aFailingSaveKeepsTheEditsInTheRecoveryCopy() async throws {
        let session = try await open()
        await store.failSaves(with: .io("The disk is full."))
        session.select(key: 13)
        session.setCode("KC_Q")
        await session.flush()
        #expect(session.saveError != nil)
        #expect(await store.recovery(of: session.id) == session.layout)

        await store.failSaves(with: nil)
        session.setCode("KC_W")
        await session.flush()
        #expect(await store.layout(session.id) == session.layout)
        #expect(await store.recovery(of: session.id) == nil, "a landed save drops the copy")
    }

    @Test func anEditInsideTheAutosaveDelayIsCopiedAtOnce() async throws {
        let session = try await open(autosaveDelay: .seconds(3600))
        session.select(key: 13)
        session.setCode("KC_Q")
        for _ in 0..<500 where await store.recovery(of: session.id) == nil { try await Task.sleep(for: .milliseconds(2)) }
        #expect(await store.recovery(of: session.id) == session.layout)
        #expect(await store.layout(session.id) != session.layout, "the autosave hasn't run")
    }

    @Test func openingRestoresANewerRecoveryCopy() async throws {
        let first = try await open()
        let id = first.id
        var edited = first.layout
        edited.updateKey(layer: 0, index: 13) { $0 = Key("KC_Q") }
        await store.saveRecovery(edited, for: id)

        // A new launch: another Library over the same store.
        let session = try await Library(store: store).open(id, autosaveDelay: .milliseconds(1))
        #expect(session.layout == edited)
        #expect(session.recoveredUnsavedChanges)
        #expect(session.isEditedSinceRevision)
        await session.flush()
        #expect(await store.layout(id) == edited, "the recovered edits are saved")
        #expect(await store.recovery(of: id) == nil)
    }

    @Test func aRecoveryCopyEqualToTheSavedLayoutIsDropped() async throws {
        let first = try await open()
        await store.saveRecovery(first.layout, for: first.id)
        let session = try await Library(store: store).open(first.id)
        #expect(!session.recoveredUnsavedChanges)
        #expect(await store.recovery(of: first.id) == nil)
    }
}
