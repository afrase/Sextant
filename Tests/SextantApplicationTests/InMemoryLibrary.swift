import Foundation
import SextantApplication
import SextantDomain

/// An in-memory `LayoutLibrary` fake that records saves.
actor InMemoryLibrary: LayoutLibrary {
    struct Item {
        var entry: LibraryEntry
        var layout: KeyboardLayout
        var revisions: [RevisionSummary] = []
        /// The layout each revision recorded, by revision id.
        var revisionLayouts: [String: KeyboardLayout] = [:]
        var firmware: [String: (data: Data, md5: String)] = [:]
    }

    private(set) var items: [UUID: Item] = [:]
    private(set) var saveCount = 0
    private var loadHook: (@Sendable () async -> Void)?
    private var appendHook: (@Sendable () async -> Void)?

    func entries() -> [LibraryEntry] { items.values.map(\.entry).sorted { $0.modifiedAt > $1.modifiedAt } }

    /// Runs `body` at the start of every load, e.g. to change the UI while a save is in flight.
    func beforeLoad(_ body: @escaping @Sendable () async -> Void) { loadHook = body }

    func load(_ id: UUID) async throws(LibraryError) -> StoredLayout {
        await loadHook?()
        guard let i = items[id] else { throw .notFound(id) }
        return StoredLayout(entry: i.entry, layout: i.layout, contentHash: Self.hash(i.layout), revisions: i.revisions)
    }

    func create(_ layout: KeyboardLayout, origin: LayoutOrigin, firstRevision: RevisionDraft?) async throws(LibraryError) -> LibraryEntry {
        let entry = LibraryEntry(id: UUID(), title: layout.title, origin: origin, modifiedAt: Date())
        items[entry.id] = Item(entry: entry, layout: layout)
        if let firstRevision { _ = try await appendRevision(firstRevision, to: entry.id) }
        return entry
    }

    /// When set, every `save` fails with this error (disk full, permissions).
    var saveFailure: LibraryError?
    func failSaves(with error: LibraryError?) { saveFailure = error }

    func save(_ layout: KeyboardLayout, to id: UUID) throws(LibraryError) {
        if let saveFailure { throw saveFailure }
        guard var item = items[id] else { throw .notFound(id) }
        item.layout = layout
        item.entry.title = layout.title
        item.entry.origin = item.entry.origin.following(layout)
        items[id] = item
        saveCount += 1
    }

    /// Runs `body` at the start of every revision append, e.g. to make recording a flash take as long as a disk write.
    func beforeAppend(_ body: @escaping @Sendable () async -> Void) { appendHook = body }

    func appendRevision(_ draft: RevisionDraft, to id: UUID) async throws(LibraryError) -> RevisionSummary {
        await appendHook?()
        guard let item = items[id] else { throw .notFound(id) }
        let n = item.revisions.count + 1
        let s = RevisionSummary(
            id: "\(n)", number: n, createdAt: Date(), source: draft.source, message: draft.message,
            contentHash: Self.hash(draft.layout))
        items[id]?.revisions.append(s)
        items[id]?.revisionLayouts[s.id] = draft.layout
        return s
    }

    func layout(ofRevision revisionID: String, in id: UUID) throws(LibraryError) -> KeyboardLayout {
        guard let layout = items[id]?.revisionLayouts[revisionID] else { throw .notFound(id) }
        return layout
    }

    func rename(_ id: UUID, to title: String) throws(LibraryError) {
        guard items[id] != nil else { throw .notFound(id) }
        items[id]?.entry.title = title
        items[id]?.layout.title = title
    }

    func duplicate(_ id: UUID) async throws(LibraryError) -> LibraryEntry {
        let stored = try await load(id)
        return try await create(stored.layout, origin: .local, firstRevision: nil)
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

    /// Recovery copies by layout; the fake keeps whatever was written last.
    private(set) var recoveries: [UUID: KeyboardLayout] = [:]
    func saveRecovery(_ layout: KeyboardLayout, for id: UUID) { recoveries[id] = layout }
    func recovery(of id: UUID) -> KeyboardLayout? { recoveries[id] }
    func discardRecovery(of id: UUID) { recoveries[id] = nil }

    func layout(_ id: UUID) -> KeyboardLayout? { items[id]?.layout }

    /// Equal layouts hash equally within a test run, like storage's canonical hash.
    static func hash(_ layout: KeyboardLayout) -> String { "h\(layout.hashValue)" }
}

enum Fixtures {
    static let userLayoutData = (try? data("my-layout-KlgM7-40xJ7M.json")) ?? Data()

    static let examples = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "docs/research/oryx-examples")

    /// Other people's Oryx samples are kept out of the repo, at the same path under `$SEXTANT_REFERENCE`; nil (unset,
    /// or no such folder) skips the tests that need them.
    static let reference = ProcessInfo.processInfo.environment["SEXTANT_REFERENCE"]
        .map { URL(fileURLWithPath: $0).appending(path: "docs/research/oryx-examples") }
        .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }

    /// A file under `docs/research/oryx-examples/` (never copied into the test bundle): the repo's copy if there is
    /// one, else the reference folder's.
    static func data(_ name: String) throws -> Data {
        let own = examples.appending(path: name)
        return try Data(contentsOf: FileManager.default.fileExists(atPath: own.path) ? own : (reference ?? examples).appending(path: name))
    }
}
