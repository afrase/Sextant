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
    /// The library has been read once, so empty ``entries`` mean an empty library (the Welcome) rather than loading.
    public private(set) var hasLoaded = false

    @ObservationIgnored private let store: any LayoutLibrary
    /// Open documents, one per layout: an import lands in the open one instead of behind it, and no second copy's
    /// autosave can overwrite the first's edits.
    @ObservationIgnored private var sessions: [UUID: OpenSession] = [:]
    /// Layouts being loaded, so two windows opening at once can't both take the same one.
    @ObservationIgnored private var opening: Set<UUID> = []
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
        hasLoaded = true
    }

    /// True while a window has the layout open, or is opening it. A layout has one window (spec §2.1).
    public func isOpen(_ id: UUID) -> Bool { opening.contains(id) || sessions[id]?.session != nil }

    /// Opens a layout for editing. Windows check ``isOpen(_:)`` first, and ``close(_:)`` the session when done.
    public func open(_ id: UUID, autosaveDelay: Duration = .seconds(1)) async throws(LibraryError) -> EditSession {
        opening.insert(id)
        defer { opening.remove(id) }
        // A document whose window went away can still hold its last edit: write it before reading the file.
        await sessions[id]?.session?.flush()
        let session = EditSession(stored: try await store.load(id), library: store, autosaveDelay: autosaveDelay)
        sessions[id] = OpenSession(session: session)
        return session
    }

    /// Lets a layout go when its window closes or switches away: writes its last edit, then frees it for other windows.
    public func close(_ session: EditSession) async {
        await session.flush()
        if sessions[session.id]?.session === session { sessions[session.id] = nil }
    }

    /// Writes every open document's pending edit now (before quitting).
    public func flushOpenSessions() async {
        for session in sessions.values.compactMap(\.session) { await session.flush() }
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
    ///
    /// With `existing`, the import becomes a new revision of that layout instead, made through its open document
    /// when there is one (undoable there): see ``EditSession/applyImport(_:)``.
    /// `firmware` is Oryx's md5-verified image for the layout's revision; it is kept when given.
    @discardableResult
    public func add(
        imported layout: KeyboardLayout, asRevisionOf existing: UUID? = nil, firmware: Data? = nil
    ) async throws(LibraryError) -> LibraryEntry {
        var layout = layout
        layout.title = Self.cleanImportedTitle(layout.title)
        let entry: LibraryEntry
        if let existing {
            let session = if let open = sessions[existing]?.session { open } else { try await open(existing) }
            try await session.applyImport(layout)
            entry = try await store.load(existing).entry
        } else {
            let origin: LayoutOrigin = layout.oryx.map { .oryx(layoutId: $0.layoutId, revisionId: $0.revisionId) } ?? .local
            entry = try await store.create(
                layout, origin: origin,
                firstRevision: RevisionDraft(source: .import, message: layout.oryx?.message, layout: layout))
        }
        if let firmware, let info = layout.oryx, let md5 = info.md5 {
            do {
                try await store.storeFirmware(firmware, md5: md5, revisionID: info.revisionId, to: entry.id)
            } catch {
                // The layout is in; Oryx's build is only a fallback to building locally.
                log.error("Keeping Oryx's firmware failed: \(String(describing: error), privacy: .public)")
            }
        }
        log.info("Imported layout \(entry.id, privacy: .public)")
        await refresh()
        return entry
    }

    /// Adds a new local layout (File ▸ New Layout) with a first revision, so it starts unedited. Nil when it couldn't
    /// be written (see ``lastError``).
    @discardableResult
    public func create(_ layout: KeyboardLayout) async -> LibraryEntry? {
        var entry: LibraryEntry?
        let first = RevisionDraft(source: .save, message: String(localized: "New layout"), layout: layout)
        await run { () throws(LibraryError) in entry = try await self.store.create(layout, origin: .local, firstRevision: first) }
        return entry
    }

    /// Renames a layout. An open document renames itself (undoably, in its window), so its next autosave can't put the
    /// old title back.
    public func rename(_ id: UUID, to title: String) async {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if let session = sessions[id]?.session {
            session.setTitle(t)
            await session.flush()
        }
        await run { () throws(LibraryError) in try await self.store.rename(id, to: t) }
    }

    /// Copies a layout, including an open document's last edit.
    @discardableResult
    public func duplicate(_ id: UUID) async -> LibraryEntry? {
        await sessions[id]?.session?.flush()
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

    private struct OpenSession { weak var session: EditSession? }

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
