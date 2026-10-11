import Foundation
import SextantApplication
import SextantDomain
import Testing

@testable import SextantStorage

/// Contract tests for the `.sextant` package library, against a temporary folder.
struct PackageLibraryTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "sextant-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    let layout: KeyboardLayout
    let library: PackageLibrary

    init() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "docs/research/oryx-examples/my-layout-KlgM7-40xJ7M.json")
        layout = try KeyboardLayout(oryxJSON: Data(contentsOf: url))
        library = PackageLibrary(root: root, moveToTrash: { try FileManager.default.removeItem(at: $0) })
    }

    @Test func createsAndLoadsAPackage() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let entry = try await library.create(
            layout, origin: .oryx(layoutId: "KlgM7", revisionId: "40xJ7M"), firstRevision: RevisionDraft(source: .import, layout: layout))
        let stored = try await library.load(entry.id)
        #expect(stored.layout == layout)
        #expect(stored.entry.origin == .oryx(layoutId: "KlgM7", revisionId: "40xJ7M"))
        #expect(stored.revisions.count == 1)
        #expect(stored.revisions[0].id.hasPrefix("0001-"))
        #expect(stored.revisions[0].contentHash.hasPrefix("sha256:"))
        #expect(!stored.hasEditsSinceLastRevision, "the working copy's hash matches its import revision's")
        let folder = try #require(await library.location(of: entry.id))
        #expect(folder.pathExtension == "sextant")
        for file in ["meta.json", "layout.json", "revisions/\(stored.revisions[0].id).json"] {
            #expect(FileManager.default.fileExists(atPath: folder.appending(path: file).path), "\(file)")
        }
    }

    @Test func savesAndAppendsRevisions() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let entry = try await library.create(layout, origin: .local, firstRevision: nil)
        var edited = layout
        edited.title = "Edited"
        edited.updateKey(layer: 0, index: 1) { $0 = Key("KC_Q") }
        try await library.save(edited, to: entry.id)
        let r1 = try await library.appendRevision(RevisionDraft(source: .save, message: "one", layout: edited), to: entry.id)
        let r2 = try await library.appendRevision(RevisionDraft(source: .flash, layout: edited), to: entry.id)
        #expect(r1.number == 1 && r2.number == 2)
        #expect(r1.contentHash == r2.contentHash, "same content, same hash")
        let stored = try await library.load(entry.id)
        #expect(stored.layout == edited)
        #expect(stored.entry.title == "Edited")
        #expect(stored.revisions.map(\.source) == [.save, .flash])
        #expect(!stored.hasEditsSinceLastRevision)
        try await library.save(layout, to: entry.id)
        #expect(try await library.load(entry.id).hasEditsSinceLastRevision)
    }

    @Test func renamesDuplicatesAndTrashes() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let entry = try await library.create(layout, origin: .local, firstRevision: nil)
        try await library.rename(entry.id, to: "Work: Main")
        let folder = try #require(await library.location(of: entry.id))
        #expect(folder.lastPathComponent.hasPrefix("Work- Main-"), "\(folder.lastPathComponent)")
        #expect(try await library.load(entry.id).layout.title == "Work: Main")
        let copy = try await library.duplicate(entry.id)
        #expect(copy.title == "Work: Main Copy" && copy.origin == .local)
        #expect(try await library.entries().count == 2)
        try await library.trash(entry.id)
        #expect(try await library.entries().map(\.id) == [copy.id])
        await #expect(throws: LibraryError.notFound(entry.id)) { try await library.load(entry.id) }
    }

    @Test func refusesNewerFormats() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let entry = try await library.create(layout, origin: .local, firstRevision: nil)
        let meta = try #require(await library.location(of: entry.id)).appending(path: "meta.json")
        let text = try String(contentsOf: meta, encoding: .utf8).replacingOccurrences(
            of: "\"formatVersion\" : 1", with: "\"formatVersion\" : 2")
        try text.write(to: meta, atomically: true, encoding: .utf8)
        await #expect(throws: LibraryError.newerFormat(2)) { try await library.load(entry.id) }
    }

    @Test func anOryxOriginFollowsTheImportedRevision() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let imported = try await library.create(layout, origin: .oryx(layoutId: "KlgM7", revisionId: "40xJ7M"), firstRevision: nil)
        let local = try await library.create(layout, origin: .local, firstRevision: nil)
        var newer = layout
        newer.oryx?.revisionId = "N3wRev"
        try await library.save(newer, to: imported.id)
        try await library.save(newer, to: local.id)
        #expect(try await library.load(imported.id).entry.origin == .oryx(layoutId: "KlgM7", revisionId: "N3wRev"))
        #expect(try await library.load(local.id).entry.origin == .local)

        var other = newer
        other.oryx?.layoutId = "Other1"
        try await library.save(other, to: imported.id)
        #expect(try await library.load(imported.id).entry.origin == .oryx(layoutId: "KlgM7", revisionId: "N3wRev"))
    }

    @Test func keepsFirmwarePerRevision() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let entry = try await library.create(layout, origin: .local, firstRevision: nil)
        #expect(try await library.firmware(revisionID: "40xJ7M", of: entry.id) == nil)

        try await library.storeFirmware(Data([1, 2, 3]), md5: "ABC123", revisionID: "40xJ7M", to: entry.id)
        let folder = try #require(await library.location(of: entry.id))
        for file in ["firmware/40xJ7M.bin", "firmware/40xJ7M.bin.md5"] {
            #expect(FileManager.default.fileExists(atPath: folder.appending(path: file).path), "\(file)")
        }
        var kept = try #require(try await library.firmware(revisionID: "40xJ7M", of: entry.id))
        #expect(kept.data == Data([1, 2, 3]) && kept.md5 == "abc123")

        try await library.storeFirmware(Data([4]), md5: "def456", revisionID: "40xJ7M", to: entry.id)
        kept = try #require(try await library.firmware(revisionID: "40xJ7M", of: entry.id))
        #expect(kept.data == Data([4]) && kept.md5 == "def456", "a rebuilt revision replaces its image")
        #expect(try await library.firmware(revisionID: "0002-3b9f2c1e", of: entry.id) == nil)

        try FileManager.default.removeItem(at: folder.appending(path: "firmware/40xJ7M.bin.md5"))
        #expect(try await library.firmware(revisionID: "40xJ7M", of: entry.id) == nil, "an image without its md5 isn't kept")
    }

    @Test func refusesFirmwareOutsideThePackage() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let entry = try await library.create(layout, origin: .local, firstRevision: nil)
        for id in ["", "../escape", "a/b", ".hidden", String(repeating: "x", count: 65)] {
            await #expect(throws: LibraryError.self) { try await library.storeFirmware(Data(), md5: "", revisionID: id, to: entry.id) }
            await #expect(throws: LibraryError.self) { try await library.firmware(revisionID: id, of: entry.id) }
        }
        let missing = UUID()
        await #expect(throws: LibraryError.notFound(missing)) {
            try await library.storeFirmware(Data(), md5: "", revisionID: "40xJ7M", to: missing)
        }
    }

    @Test func anEmptyLibraryHasNoEntries() async throws {
        #expect(try await library.entries().isEmpty)
    }

    @Test func hashIsStableAndContentSensitive() throws {
        var other = layout
        other.title = "x"
        let first = try PackageLibrary.contentHash(layout), second = try PackageLibrary.contentHash(layout)
        #expect(first == second)
        #expect(try first != PackageLibrary.contentHash(other))
    }
}
