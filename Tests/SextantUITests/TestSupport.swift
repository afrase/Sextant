import Foundation
import SextantApplication
import SextantDomain

@testable import SextantUI

/// The user's real layout ("My MacOS Layout": Main, Sym+Num #00F0FF, Brd+Sys #42FF00).
let userLayoutData = try? Data(
    contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "docs/research/oryx-examples/my-layout-KlgM7-40xJ7M.json"))

/// Other people's Oryx samples are kept out of the repo, at the same path under `$SEXTANT_REFERENCE`; nil (unset, or no
/// such folder) skips the tests that need them.
let referenceExamples = ProcessInfo.processInfo.environment["SEXTANT_REFERENCE"]
    .map { URL(fileURLWithPath: $0).appending(path: "docs/research/oryx-examples") }
    .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }

/// An Oryx example under `docs/research/oryx-examples/`: the repo's copy if there is one, else the reference folder's.
func exampleURL(_ name: String) -> URL {
    let examples = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "docs/research/oryx-examples")
    let own = examples.appending(path: name)
    return FileManager.default.fileExists(atPath: own.path) ? own : (referenceExamples ?? examples).appending(path: name)
}

/// Committed pixel references are rendered on the developer's macOS; CI's fonts and drawing differ slightly.
let skipsPixelSnapshots = ProcessInfo.processInfo.environment["CI"]?.isEmpty == false

/// A window model with the user's layout open.
@MainActor
func openUserLayout() async throws -> LayoutWindowModel {
    let library = Library(store: MemoryLibrary())
    let data = try userLayoutData ?? { throw CocoaError(.fileNoSuchFile) }()
    _ = try await library.importOryxJSON(data)
    let model = LayoutWindowModel(library: library)
    await model.open(nil)
    return model
}

/// A minimal in-memory library for view-model tests.
actor MemoryLibrary: LayoutLibrary {
    var items: [UUID: (LibraryEntry, KeyboardLayout)] = [:]
    func entries() -> [LibraryEntry] { items.values.map(\.0) }
    func load(_ id: UUID) throws(LibraryError) -> StoredLayout {
        guard let (e, l) = items[id] else { throw .notFound(id) }
        // As imported: one revision whose content equals the working copy.
        let imported = RevisionSummary(id: "1", number: 1, createdAt: e.modifiedAt, source: .import, message: nil, contentHash: "")
        return StoredLayout(entry: e, layout: l, contentHash: "", revisions: [imported])
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
    func layout(ofRevision revisionID: String, in id: UUID) throws(LibraryError) -> KeyboardLayout {
        guard let (_, l) = items[id] else { throw .notFound(id) }
        return l  // `save` keeps nothing, so the stored layout is still the import
    }
    func storeFirmware(_ data: Data, md5: String, revisionID: String, to id: UUID) {}
    func firmware(revisionID: String, of id: UUID) -> (data: Data, md5: String)? { nil }
    func location(of id: UUID) -> URL? { nil }
    var recoveries: [UUID: KeyboardLayout] = [:]
    func saveRecovery(_ layout: KeyboardLayout, for id: UUID) { recoveries[id] = layout }
    func recovery(of id: UUID) -> KeyboardLayout? { recoveries[id] }
    func discardRecovery(of id: UUID) { recoveries[id] = nil }
    var appLayers: [UUID: AppLayerRules] = [:]
    func appLayerRules(of id: UUID) -> AppLayerRules { appLayers[id] ?? AppLayerRules() }
    func saveAppLayerRules(_ rules: AppLayerRules, for id: UUID) { appLayers[id] = rules }
}
