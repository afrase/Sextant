import Foundation
import SextantApplication
import SextantDomain
import Testing

@testable import SextantUI

@MainActor
struct LayoutWindowModelTests {
    let layoutData = try? Data(
        contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "docs/research/oryx-examples/my-layout-KlgM7-40xJ7M.json"))

    @Test func opensTheMostRecentLayoutAndKeepsItsSession() async throws {
        let library = Library(store: MemoryLibrary())
        #expect(await LayoutWindowModel(library: library).open(nil) == nil, "an empty library opens nothing")
        let entry = try await library.importOryxJSON(try #require(layoutData))
        let model = LayoutWindowModel(library: library)
        #expect(await model.open(nil) == entry.id)
        let session = try #require(model.session)
        #expect(await model.open(entry.id) == entry.id)
        #expect(model.session === session, "opening the same layout keeps the session")
        #expect(await model.open(UUID()) == entry.id, "a stale restored id falls back to the most recent layout")
        #expect(model.loadError == nil)
    }
}

/// A minimal in-memory library for view-model tests.
private actor MemoryLibrary: LayoutLibrary {
    var items: [UUID: (LibraryEntry, KeyboardLayout)] = [:]
    func entries() -> [LibraryEntry] { items.values.map(\.0) }
    func load(_ id: UUID) throws(LibraryError) -> StoredLayout {
        guard let (e, l) = items[id] else { throw .notFound(id) }
        return StoredLayout(entry: e, layout: l, contentHash: "", revisions: [])
    }
    func create(_ layout: KeyboardLayout, origin: LayoutOrigin, firstRevision: RevisionDraft?) -> LibraryEntry {
        let e = LibraryEntry(id: UUID(), title: layout.title, origin: origin, modifiedAt: Date())
        items[e.id] = (e, layout)
        return e
    }
    func save(_ layout: KeyboardLayout, to id: UUID) {}
    func appendRevision(_ draft: RevisionDraft, to id: UUID) -> RevisionSummary {
        RevisionSummary(id: "1", number: 1, createdAt: Date(), source: draft.source, message: nil, contentHash: "")
    }
    func rename(_ id: UUID, to title: String) {}
    func duplicate(_ id: UUID) throws(LibraryError) -> LibraryEntry { throw .notFound(id) }
    func trash(_ id: UUID) {}
    func location(of id: UUID) -> URL? { nil }
    func storeFirmware(_ data: Data, md5: String, revisionID: String, to id: UUID) {}
    func firmware(revisionID: String, of id: UUID) -> (data: Data, md5: String)? { nil }
}
