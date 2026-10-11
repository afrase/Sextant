import Foundation
import Observation
import SextantDomain
import os

/// The layout library as the app sees it: list, open, import files, and manage layouts.
@MainActor
@Observable
public final class Library {
    /// Every layout, most recently modified first.
    public private(set) var entries: [LibraryEntry] = []
    /// The last error from a library operation, for the UI to show.
    public var lastError: LibraryError?

    @ObservationIgnored private let store: any LayoutLibrary
    @ObservationIgnored private let log = Logger(subsystem: "com.sextant.app", category: "application")

    public init(store: any LayoutLibrary) {
        self.store = store
    }

    /// Re-reads the library.
    public func refresh() async {
        do {
            entries = try await store.entries()
        } catch {
            fail(error)
        }
    }

    /// Opens a layout for editing.
    public func open(_ id: UUID, autosaveDelay: Duration = .seconds(1)) async throws(LibraryError) -> EditSession {
        let stored = try await store.load(id)
        return EditSession(stored: stored, library: store, autosaveDelay: autosaveDelay)
    }

    /// Imports an Oryx layout JSON file (GraphQL response or bare layout) as a new library layout,
    /// recording the import as its first revision.
    @discardableResult
    public func importOryxJSON(_ data: Data) async throws(LibraryError) -> LibraryEntry {
        let layout: KeyboardLayout
        do {
            layout = try KeyboardLayout(oryxJSON: data)
        } catch {
            throw .unreadable(String(describing: error))
        }
        return try await add(imported: layout)
    }

    /// Adds an imported layout: strips Oryx's " [fork]" suffix and records an import revision (spec §2.3).
    @discardableResult
    public func add(imported layout: KeyboardLayout) async throws(LibraryError) -> LibraryEntry {
        var layout = layout
        layout.title = Self.cleanImportedTitle(layout.title)
        let origin: LayoutOrigin = layout.oryx.map { .oryx(layoutId: $0.layoutId, revisionId: $0.revisionId) } ?? .local
        let entry = try await store.create(
            layout, origin: origin,
            firstRevision: RevisionDraft(source: .import, message: layout.oryx?.message, layout: layout))
        log.info("Imported layout \(entry.id, privacy: .public)")
        await refresh()
        return entry
    }

    public func rename(_ id: UUID, to title: String) async {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        await run { () throws(LibraryError) in try await self.store.rename(id, to: t) }
    }

    @discardableResult
    public func duplicate(_ id: UUID) async -> LibraryEntry? {
        var copy: LibraryEntry?
        await run { () throws(LibraryError) in copy = try await self.store.duplicate(id) }
        return copy
    }

    public func trash(_ id: UUID) async {
        await run { () throws(LibraryError) in try await self.store.trash(id) }
    }

    public func location(of id: UUID) async -> URL? { await store.location(of: id) }

    /// Oryx appends " [fork]" to forked layouts' titles; Sextant drops it on import.
    nonisolated static func cleanImportedTitle(_ title: String) -> String {
        var t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasSuffix("[fork]") { t = String(t.dropLast("[fork]".count)).trimmingCharacters(in: .whitespaces) }
        return t.isEmpty ? String(localized: "Untitled Layout") : t
    }

    private func run(_ body: () async throws(LibraryError) -> Void) async {
        do {
            try await body()
        } catch {
            fail(error)
        }
        await refresh()
    }

    private func fail(_ error: LibraryError) {
        log.error("Library: \(String(describing: error), privacy: .public)")
        lastError = error
    }
}
