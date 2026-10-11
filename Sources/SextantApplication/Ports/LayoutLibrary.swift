import Foundation
import SextantDomain

/// Where a library layout came from.
public enum LayoutOrigin: Hashable, Sendable {
    /// Made in Sextant (blank, duplicated, or an imported file without Oryx ids).
    case local
    /// Imported read-only from Oryx.
    case oryx(layoutId: String, revisionId: String)

    /// The origin once `layout` is the working copy: an Oryx origin follows an import of the same Oryx layout.
    public func following(_ layout: KeyboardLayout) -> Self {
        guard case let .oryx(layoutId, _) = self, let oryx = layout.oryx, oryx.layoutId == layoutId else { return self }
        return .oryx(layoutId: layoutId, revisionId: oryx.revisionId)
    }
}

/// One layout in the library, as the sidebar lists it.
public struct LibraryEntry: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var origin: LayoutOrigin
    public var modifiedAt: Date

    public init(id: UUID, title: String, origin: LayoutOrigin, modifiedAt: Date) {
        self.id = id
        self.title = title
        self.origin = origin
        self.modifiedAt = modifiedAt
    }
}

/// What made a revision (spec §2.3: imports, flashes and ⌘S create revisions).
public enum RevisionSource: String, Hashable, Sendable, Codable {
    case `import`, flash, save
}

/// A revision to append: an immutable checkpoint of the layout.
public struct RevisionDraft: Sendable {
    public var source: RevisionSource
    public var message: String?
    public var layout: KeyboardLayout

    public init(source: RevisionSource, message: String? = nil, layout: KeyboardLayout) {
        self.source = source
        self.message = message
        self.layout = layout
    }
}

/// A stored revision's metadata.
public struct RevisionSummary: Identifiable, Hashable, Sendable {
    /// Stable id, e.g. `0001-3b9f2c1e` (number plus the first 8 hex digits of the content hash).
    public var id: String
    public var number: Int
    public var createdAt: Date
    public var source: RevisionSource
    public var message: String?
    /// `sha256:<hex>` of the canonical layout JSON.
    public var contentHash: String

    public init(id: String, number: Int, createdAt: Date, source: RevisionSource, message: String?, contentHash: String) {
        self.id = id
        self.number = number
        self.createdAt = createdAt
        self.source = source
        self.message = message
        self.contentHash = contentHash
    }
}

/// A layout loaded from the library.
public struct StoredLayout: Sendable {
    public var entry: LibraryEntry
    public var layout: KeyboardLayout
    /// The working copy's hash, comparable with ``RevisionSummary/contentHash``.
    public var contentHash: String
    /// Oldest first.
    public var revisions: [RevisionSummary]

    public init(entry: LibraryEntry, layout: KeyboardLayout, contentHash: String, revisions: [RevisionSummary]) {
        self.entry = entry
        self.layout = layout
        self.contentHash = contentHash
        self.revisions = revisions
    }

    /// Whether the working copy differs from the latest revision.
    public var hasEditsSinceLastRevision: Bool { contentHash != revisions.last?.contentHash }
}

/// Errors from the layout library.
public enum LibraryError: Error, Equatable, Sendable, LocalizedError {
    case notFound(UUID)
    /// The package was written by a newer Sextant.
    case newerFormat(Int)
    /// A file in the package (or an imported file) isn't a layout Sextant can read. The detail is for the log.
    case unreadable(String)
    /// The detail is for the log.
    case io(String)

    public var errorDescription: String? {
        switch self {
        case .notFound: String(localized: "This layout is no longer in your library.")
        case .newerFormat: String(localized: "This layout was saved by a newer version of Sextant. Update Sextant to open it.")
        case .unreadable: String(localized: "Sextant couldn't read this layout. The file may be damaged.")
        case .io: String(localized: "Sextant couldn't save or load the layout. Check that the disk has space and try again.")
        }
    }
}

/// The library of `.sextant` packages (architecture §6).
public protocol LayoutLibrary: Sendable {
    /// Every layout, most recently modified first.
    func entries() async throws(LibraryError) -> [LibraryEntry]
    func load(_ id: UUID) async throws(LibraryError) -> StoredLayout
    /// Adds a layout, optionally with its first revision (an import records one).
    func create(_ layout: KeyboardLayout, origin: LayoutOrigin, firstRevision: RevisionDraft?) async throws(LibraryError) -> LibraryEntry
    /// Overwrites the working copy (autosave). An Oryx origin follows the layout's Oryx revision when an import
    /// of the same Oryx layout replaces the working copy.
    func save(_ layout: KeyboardLayout, to id: UUID) async throws(LibraryError)
    func appendRevision(_ draft: RevisionDraft, to id: UUID) async throws(LibraryError) -> RevisionSummary
    /// The layout a revision recorded (the firmware identity rule compares against the latest import).
    func layout(ofRevision revisionID: String, in id: UUID) async throws(LibraryError) -> KeyboardLayout
    func rename(_ id: UUID, to title: String) async throws(LibraryError)
    func duplicate(_ id: UUID) async throws(LibraryError) -> LibraryEntry
    /// Moves the layout to the Trash.
    func trash(_ id: UUID) async throws(LibraryError)
    /// Keeps a firmware image for one of the layout's revisions with its md5, replacing any image kept for it.
    func storeFirmware(_ data: Data, md5: String, revisionID: String, to id: UUID) async throws(LibraryError)
    /// The firmware image kept for a revision and its md5, or nil when none is kept.
    func firmware(revisionID: String, of id: UUID) async throws(LibraryError) -> (data: Data, md5: String)?
    /// The package folder, for Show in Finder.
    func location(of id: UUID) async -> URL?
}
