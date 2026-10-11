import Foundation
import SextantApplication
import SextantDomain

/// An in-memory `LayoutLibrary` fake that records saves.
actor InMemoryLibrary: LayoutLibrary {
    struct Item {
        var entry: LibraryEntry
        var layout: KeyboardLayout
        var revisions: [RevisionSummary] = []
        /// The layout each revision recorded, in the same order.
        var revisionLayouts: [KeyboardLayout] = []
        var firmware: [String: (data: Data, md5: String)] = [:]
    }

    private(set) var items: [UUID: Item] = [:]
    private(set) var saveCount = 0

    func entries() -> [LibraryEntry] { items.values.map(\.entry).sorted { $0.modifiedAt > $1.modifiedAt } }

    func load(_ id: UUID) throws(LibraryError) -> StoredLayout {
        guard let i = items[id] else { throw .notFound(id) }
        return StoredLayout(entry: i.entry, layout: i.layout, revisions: i.revisions)
    }

    func create(_ layout: KeyboardLayout, origin: LayoutOrigin, firstRevision: RevisionDraft?) throws(LibraryError) -> LibraryEntry {
        let entry = LibraryEntry(id: UUID(), title: layout.title, origin: origin, modifiedAt: Date())
        items[entry.id] = Item(entry: entry, layout: layout)
        if let firstRevision { _ = try appendRevision(firstRevision, to: entry.id) }
        return entry
    }

    func save(_ layout: KeyboardLayout, to id: UUID) throws(LibraryError) {
        guard items[id] != nil else { throw .notFound(id) }
        items[id]?.layout = layout
        items[id]?.entry.title = layout.title
        saveCount += 1
    }

    func appendRevision(_ draft: RevisionDraft, to id: UUID) throws(LibraryError) -> RevisionSummary {
        guard let item = items[id] else { throw .notFound(id) }
        let n = item.revisions.count + 1
        let s = RevisionSummary(
            id: "\(n)", number: n, createdAt: Date(), source: draft.source, message: draft.message, contentHash: "h\(n)")
        items[id]?.revisions.append(s)
        items[id]?.revisionLayouts.append(draft.layout)
        return s
    }

    func rename(_ id: UUID, to title: String) throws(LibraryError) {
        guard items[id] != nil else { throw .notFound(id) }
        items[id]?.entry.title = title
        items[id]?.layout.title = title
    }

    func duplicate(_ id: UUID) throws(LibraryError) -> LibraryEntry {
        let stored = try load(id)
        return try create(stored.layout, origin: .local, firstRevision: nil)
    }

    func trash(_ id: UUID) throws(LibraryError) {
        guard items.removeValue(forKey: id) != nil else { throw .notFound(id) }
    }

    func location(of id: UUID) -> URL? { nil }

    func storeFirmware(_ data: Data, md5: String, revisionID: String, to id: UUID) throws(LibraryError) {
        guard items[id] != nil else { throw .notFound(id) }
        items[id]?.firmware[revisionID] = (data, md5)
    }

    func firmware(revisionID: String, of id: UUID) throws(LibraryError) -> (data: Data, md5: String)? {
        guard let item = items[id] else { throw .notFound(id) }
        return item.firmware[revisionID]
    }

    func layout(_ id: UUID) -> KeyboardLayout? { items[id]?.layout }
}

enum Fixtures {
    static let userLayoutData = (try? data("my-layout-KlgM7-40xJ7M.json")) ?? Data()

    /// A file under `docs/research/oryx-examples/` (never copied into the test bundle).
    static func data(_ name: String) throws -> Data {
        try Data(
            contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().appending(path: "docs/research/oryx-examples/\(name)"))
    }
}
