import CryptoKit
import Foundation
import SextantApplication
import SextantDomain
import os

/// The layout library as a folder of `.sextant` packages (architecture §6, ADR 0007).
///
/// ```
/// <root>/<Title>-<id6>.sextant/
///   meta.json            format version, id, title, origin, dates, content hash, aliases (ids on other Macs, ADR 0061)
///   layout.json          the working copy (Oryx-shaped layout JSON)
///   revisions/NNNN-<hash8>.json   append-only checkpoints
///   firmware/<revision>.bin       an Oryx- or Sextant-built image, plus <revision>.bin.md5
///   app-layers.json      App Layers: rules kept beside the layout, outside its content hash (ADR 0054)
/// <root>/.recovery/<id>.json   the latest edits until their autosave lands
/// ```
public actor PackageLibrary: LayoutLibrary {
    /// The newest package format this build reads. Newer packages are refused, not misread. A package is written as 2
    /// once it holds macro drafts, and as 1 until then, so an older build refuses drafts (`.newerFormat`) instead of
    /// dropping them at its next save; every other package stays readable by older builds (ADR 0042).
    public static let formatVersion = 2

    private let root: URL
    private let now: @Sendable () -> Date
    private let moveToTrash: @Sendable (URL) throws -> Void
    private var folders: [UUID: URL] = [:]
    private let log = Logger(subsystem: "com.sextant.app", category: "storage")

    /// - Parameters:
    ///   - root: the library folder; created on first write.
    ///   - now: the clock for dates (injected for tests).
    ///   - moveToTrash: how `trash(_:)` disposes of a package (the Finder Trash by default).
    public init(
        root: URL, now: @escaping @Sendable () -> Date = { Date() },
        moveToTrash: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) {
        self.root = root
        // Whole seconds, as `.iso8601` stores them, so what a call returns equals what a later read gives.
        self.now = { Date(timeIntervalSince1970: now().timeIntervalSince1970.rounded(.down)) }
        self.moveToTrash = moveToTrash
    }

    /// `~/Library/Application Support/Sextant/Library/`.
    public static func defaultRoot() -> URL {
        URL.applicationSupportDirectory.appending(path: "Sextant/Library", directoryHint: .isDirectory)
    }

    // MARK: LayoutLibrary

    public func entries() throws(LibraryError) -> [LibraryEntry] {
        try scan()
        return folders.compactMap { _, folder in
            do {
                return try readMeta(folder).entry
            } catch {
                let detail = "\(folder.lastPathComponent): \(String(describing: error))"
                log.error("Skipping unreadable package \(detail, privacy: .public)")
                return nil
            }
        }
        .sorted { ($0.modifiedAt, $0.id.uuidString) > ($1.modifiedAt, $1.id.uuidString) }
    }

    public func load(_ id: UUID) throws(LibraryError) -> StoredLayout {
        let folder = try folder(for: id)
        let meta = try readMeta(folder)
        let layout = try decode(KeyboardLayout.self, from: folder.appending(path: "layout.json"))
        // Hash what is on disk: meta.json's copy is stale if its write failed after layout.json's.
        return StoredLayout(entry: meta.entry, layout: layout, contentHash: try Self.contentHash(layout), revisions: revisions(in: folder))
    }

    public func create(_ layout: KeyboardLayout, origin: LayoutOrigin, firstRevision: RevisionDraft?) throws(LibraryError) -> LibraryEntry {
        let id = UUID()
        let folder = root.appending(
            path: "\(Self.folderName(layout.title))-\(id.uuidString.prefix(6)).sextant", directoryHint: .isDirectory)
        let date = now()
        let meta = Meta(
            formatVersion: Self.formatVersion(of: layout), id: id, title: layout.title, origin: Meta.Origin(origin),
            createdAt: date, modifiedAt: date, contentHash: try Self.contentHash(layout))
        try io { try FileManager.default.createDirectory(at: folder.appending(path: "revisions"), withIntermediateDirectories: true) }
        try write(layout, to: folder.appending(path: "layout.json"))
        try write(meta, to: folder.appending(path: "meta.json"))
        folders[id] = folder
        if let firstRevision { _ = try appendRevision(firstRevision, in: folder) }
        return meta.entry
    }

    public func save(_ layout: KeyboardLayout, to id: UUID) throws(LibraryError) {
        let folder = try folder(for: id)
        var meta = try readMeta(folder)
        let version = Self.formatVersion(of: layout, was: meta.formatVersion)
        if version > meta.formatVersion {
            // Raised before the drafts land: an older build must never find them under a version it reads.
            meta.formatVersion = version
            try write(meta, to: folder.appending(path: "meta.json"))
        }
        try write(layout, to: folder.appending(path: "layout.json"))
        meta.title = layout.title
        meta.modifiedAt = now()
        meta.contentHash = try Self.contentHash(layout)
        meta.origin = Meta.Origin(meta.origin.model.following(layout))
        try write(meta, to: folder.appending(path: "meta.json"))
    }

    public func appendRevision(_ draft: RevisionDraft, to id: UUID) throws(LibraryError) -> RevisionSummary {
        try appendRevision(draft, in: folder(for: id))
    }

    public func layout(ofRevision revisionID: String, in id: UUID) throws(LibraryError) -> KeyboardLayout {
        // The id names a file: refuse anything that could leave the revisions folder.
        guard !revisionID.isEmpty, !revisionID.contains("/"), !revisionID.hasPrefix(".") else {
            throw .unreadable("Bad revision id \(revisionID)")
        }
        let file = try folder(for: id).appending(path: "revisions/\(revisionID).json")
        guard let layout = try decode(StoredRevision.self, from: file).layout else { throw .unreadable("\(revisionID) has no layout") }
        return layout
    }

    public func rename(_ id: UUID, to title: String) throws(LibraryError) {
        let folder = try folder(for: id)
        var layout = try decode(KeyboardLayout.self, from: folder.appending(path: "layout.json"))
        layout.title = title
        try save(layout, to: id)
        let renamed = folder.deletingLastPathComponent().appending(
            path: "\(Self.folderName(title))-\(id.uuidString.prefix(6)).sextant", directoryHint: .isDirectory)
        guard renamed != folder else { return }
        try io { try FileManager.default.moveItem(at: folder, to: renamed) }
        folders[id] = renamed
    }

    public func duplicate(_ id: UUID) throws(LibraryError) -> LibraryEntry {
        var layout = try load(id).layout
        let original = layout.title
        layout.title = String(localized: "\(original) Copy")
        // A first revision, as a new layout gets, so the copy opens unedited.
        let first = RevisionDraft(source: .save, message: String(localized: "Duplicated from \(original)"), layout: layout)
        let copy = try create(layout, origin: .local, firstRevision: first)
        // The copy keeps the App Layers. They are optional beside the layout: once the copy exists, rules that can't be
        // read (damaged, or from a newer Sextant) or written leave it without them rather than fail a copy that is there.
        do throws(LibraryError) {
            let rules = try appLayerRules(of: id)
            if rules != AppLayerRules() { try saveAppLayerRules(rules, for: copy.id) }
        } catch {
            log.error("Duplicate without App Layers: \(String(describing: error), privacy: .public)")
        }
        return copy
    }

    public func appLayerRules(of id: UUID) throws(LibraryError) -> AppLayerRules {
        let file = try folder(for: id).appending(path: Self.appLayersFile)
        guard FileManager.default.fileExists(atPath: file.path) else { return AppLayerRules() }
        let stored = try decode(StoredAppLayers.self, from: file)
        guard stored.formatVersion <= Self.appLayersFormatVersion else { throw .newerFormat(stored.formatVersion) }
        return AppLayerRules(isOn: stored.isOn, rules: stored.rules)
    }

    public func saveAppLayerRules(_ rules: AppLayerRules, for id: UUID) throws(LibraryError) {
        let stored = StoredAppLayers(formatVersion: Self.appLayersFormatVersion, isOn: rules.isOn, rules: rules.rules)
        try write(stored, to: folder(for: id).appending(path: Self.appLayersFile))
    }

    /// Only `meta.json` changes, so the content hash, modification date and revisions stay as they are. Older Sextant
    /// ignores the key, so the format version doesn't move (ADR 0061).
    public func link(_ id: UUID, to ids: Set<UUID>) throws(LibraryError) {
        let folder = try folder(for: id)
        var meta = try readMeta(folder)
        let aliases = meta.entry.aliases.union(ids).subtracting([meta.id])
        guard aliases != meta.entry.aliases else { return }
        meta.aliases = Meta.stored(aliases)
        try write(meta, to: folder.appending(path: "meta.json"))
    }

    public func trash(_ id: UUID) throws(LibraryError) {
        let folder = try folder(for: id)
        try io { try moveToTrash(folder) }
        folders[id] = nil
        discardRecovery(of: id)
    }

    public func location(of id: UUID) -> URL? {
        try? folder(for: id)
    }

    public func saveRecovery(_ layout: KeyboardLayout, for id: UUID) throws(LibraryError) {
        try io { try FileManager.default.createDirectory(at: recoveryFolder, withIntermediateDirectories: true) }
        try write(layout, to: recoveryFile(id))
    }

    public func recovery(of id: UUID) -> KeyboardLayout? {
        let file = recoveryFile(id)
        guard let copied = modified(file) else { return nil }
        // Not newer than the working copy: a later save landed and only the discard was lost (a crash right after it).
        if let saved = (try? folder(for: id)).flatMap({ modified($0.appending(path: "layout.json")) }), copied <= saved {
            discardRecovery(of: id)
            return nil
        }
        do {
            return try decode(KeyboardLayout.self, from: file)
        } catch {
            // Kept, not deleted: it may be the only copy of those edits.
            log.error(
                "Unreadable recovery copy \(file.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    public func discardRecovery(of id: UUID) {
        try? FileManager.default.removeItem(at: recoveryFile(id))
    }

    public func storeFirmware(_ data: Data, md5: String, revisionID: String, to id: UUID) throws(LibraryError) {
        let bin = try firmwareFile(revisionID, in: folder(for: id))
        let sum = bin.appendingPathExtension("md5")
        // The checksum is removed first and written last, so an image is never paired with another image's md5.
        try io {
            try FileManager.default.createDirectory(at: bin.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: sum.path) { try FileManager.default.removeItem(at: sum) }
            try data.write(to: bin, options: .atomic)
            try Data(md5.lowercased().utf8).write(to: sum, options: .atomic)
        }
    }

    public func firmware(revisionID: String, of id: UUID) throws(LibraryError) -> (data: Data, md5: String)? {
        let bin = try firmwareFile(revisionID, in: folder(for: id))
        let sum = bin.appendingPathExtension("md5")
        guard FileManager.default.fileExists(atPath: bin.path), FileManager.default.fileExists(atPath: sum.path) else { return nil }
        return try io {
            (try Data(contentsOf: bin), try String(contentsOf: sum, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    // MARK: Package files

    struct Meta: Codable {
        struct Origin: Codable {
            var kind: String
            var layoutId: String?
            var revisionId: String?

            init(_ origin: LayoutOrigin) {
                switch origin {
                case .local: kind = "local"
                case let .oryx(layoutId, revisionId): (kind, self.layoutId, self.revisionId) = ("oryx", layoutId, revisionId)
                }
            }

            var model: LayoutOrigin {
                if kind == "oryx", let layoutId, let revisionId { return .oryx(layoutId: layoutId, revisionId: revisionId) }
                return .local
            }
        }

        var formatVersion: Int
        var id: UUID
        var title: String
        var origin: Origin
        var createdAt: Date
        var modifiedAt: Date
        var contentHash: String
        /// ``LibraryEntry/aliases``, sorted; nil (left out of the file) when there are none.
        var aliases: [UUID]?

        var entry: LibraryEntry {
            LibraryEntry(id: id, title: title, origin: origin.model, modifiedAt: modifiedAt, aliases: Set(aliases ?? []))
        }

        /// Aliases as the file keeps them: sorted, so the file changes only when they do, and none when empty.
        static func stored(_ aliases: Set<UUID>) -> [UUID]? {
            aliases.isEmpty ? nil : aliases.sorted { $0.uuidString < $1.uuidString }
        }
    }

    /// `app-layers.json`. Its own format version, so a newer Sextant's rules are refused rather than overwritten.
    struct StoredAppLayers: Codable {
        var formatVersion: Int
        var isOn: Bool
        var rules: [AppLayerRule]
    }

    static let appLayersFile = "app-layers.json"
    static let appLayersFormatVersion = 1

    struct StoredRevision: Codable {
        var id: String
        var number: Int
        var parent: String?
        var createdAt: Date
        var source: RevisionSource
        var message: String?
        var contentHash: String
        var layout: KeyboardLayout?

        var summary: RevisionSummary {
            RevisionSummary(id: id, number: number, createdAt: createdAt, source: source, message: message, contentHash: contentHash)
        }
    }

    private func appendRevision(_ draft: RevisionDraft, in folder: URL) throws(LibraryError) -> RevisionSummary {
        let existing = revisions(in: folder)
        let number = (existing.last?.number ?? 0) + 1
        let hash = try Self.contentHash(draft.layout)
        let hex = hash.dropFirst("sha256:".count).prefix(8)
        let revision = StoredRevision(
            id: String(format: "%04d-", number) + hex, number: number, parent: existing.last?.id, createdAt: now(),
            source: draft.source, message: draft.message, contentHash: hash, layout: draft.layout)
        let file = folder.appending(path: "revisions/\(revision.id).json")
        guard !FileManager.default.fileExists(atPath: file.path) else { throw .io("Revision \(revision.id) already exists.") }
        try write(revision, to: file)
        return revision.summary
    }

    /// Revisions in a package, oldest first. An unreadable file is logged and skipped, so one bad checkpoint
    /// can't make the layout unopenable.
    private func revisions(in folder: URL) -> [RevisionSummary] {
        let dir = folder.appending(path: "revisions", directoryHint: .isDirectory)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { url in
                do {
                    return try decode(StoredRevision.self, from: url).summary
                } catch {
                    let detail = "\(url.lastPathComponent): \(String(describing: error))"
                    log.error("Skipping unreadable revision \(detail, privacy: .public)")
                    return nil
                }
            }
            .sorted { $0.number < $1.number }
    }

    /// `firmware/<revisionID>.bin`. The id names a file, so only letters, digits, `-` and `_` are accepted.
    private func firmwareFile(_ revisionID: String, in folder: URL) throws(LibraryError) -> URL {
        guard (1...64).contains(revisionID.count),
            revisionID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        else { throw .io("Invalid revision id \(revisionID)") }
        return folder.appending(path: "firmware/\(revisionID).bin")
    }

    private func readMeta(_ folder: URL) throws(LibraryError) -> Meta {
        let meta = try decode(Meta.self, from: folder.appending(path: "meta.json"))
        guard meta.formatVersion <= Self.formatVersion else { throw .newerFormat(meta.formatVersion) }
        return meta
    }

    private func folder(for id: UUID) throws(LibraryError) -> URL {
        if let f = folders[id], FileManager.default.fileExists(atPath: f.path) { return f }
        try scan()
        guard let f = folders[id] else { throw .notFound(id) }
        return f
    }

    /// Rebuilds the id → folder map from every `*.sextant` folder's `meta.json`.
    private func scan() throws(LibraryError) {
        guard FileManager.default.fileExists(atPath: root.path) else {
            folders = [:]
            return
        }
        let items = try io { try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) }
        var map: [UUID: URL] = [:]
        for folder in items.sorted(by: { $0.path < $1.path }) where folder.pathExtension == "sextant" {
            guard let meta = try? decode(Meta.self, from: folder.appending(path: "meta.json")) else { continue }
            if let existing = map[meta.id] {
                // A copied package (Finder duplicate) shares its id: keep the folder already in use.
                let detail = "\(meta.id): \(existing.lastPathComponent) and \(folder.lastPathComponent)"
                log.error("Two packages share id \(detail, privacy: .public)")
                if folders[meta.id] == folder { map[meta.id] = folder }
                continue
            }
            map[meta.id] = folder
        }
        folders = map
    }

    // MARK: Coding

    private static func encoder(pretty: Bool) -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    /// `sha256:<hex>` of the canonical (sorted keys, compact) JSON of a layout.
    static func contentHash(_ layout: KeyboardLayout) throws(LibraryError) -> String {
        let data: Data
        do { data = try encoder(pretty: false).encode(layout) } catch { throw .unreadable(String(describing: error)) }
        return "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// 2 once a layout has macro drafts, else `was`. It never goes back down: revisions saved since may hold drafts.
    private static func formatVersion(of layout: KeyboardLayout, was: Int = 1) -> Int {
        layout.macroDrafts.isEmpty ? was : max(was, 2)
    }

    static func folderName(_ title: String) -> String {
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/:\\\0")).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var name = String(cleaned.prefix(60))
        // APFS names hold 255 UTF-16 units and one Character can take dozens: leave room for "-XXXXXX.sextant".
        while name.utf16.count > 200 { name.removeLast() }
        return name.isEmpty ? "Layout" : name
    }

    /// Inside the library (same volume, so writes stay atomic), not the temporary folder macOS empties on restart.
    private var recoveryFolder: URL { root.appending(path: ".recovery", directoryHint: .isDirectory) }
    private func recoveryFile(_ id: UUID) -> URL { recoveryFolder.appending(path: "\(id.uuidString).json") }

    private func modified(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func write(_ value: some Encodable, to url: URL) throws(LibraryError) {
        let data: Data
        do { data = try Self.encoder(pretty: true).encode(value) } catch { throw .unreadable(String(describing: error)) }
        try io { try data.write(to: url, options: .atomic) }
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) throws(LibraryError) -> T {
        let data = try io { try Data(contentsOf: url) }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        do { return try d.decode(type, from: data) } catch {
            throw .unreadable("\(url.lastPathComponent): \(error)")
        }
    }

    private func io<T>(_ body: () throws -> T) throws(LibraryError) -> T {
        do { return try body() } catch { throw .io(error.localizedDescription) }
    }
}
