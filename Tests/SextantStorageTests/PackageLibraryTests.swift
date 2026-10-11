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

    @Test func anEmptyLibraryHasNoEntries() async throws {
        #expect(try await library.entries().isEmpty)
    }

    @Test func hashIsStableAndContentSensitive() throws {
        var other = layout
        other.title = "x"
        #expect(try PackageLibrary.contentHash(layout) == PackageLibrary.contentHash(layout))
        #expect(try PackageLibrary.contentHash(layout) != PackageLibrary.contentHash(other))
    }
}
