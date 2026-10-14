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
        #expect(stored.revisions == [r1, r2], "what appendRevision returns is what a read gives, dates included")
        #expect(try await library.layout(ofRevision: r1.id, in: entry.id) == edited)
        await #expect(throws: LibraryError.self) { try await library.layout(ofRevision: "../meta", in: entry.id) }
        await #expect(throws: LibraryError.self) { try await library.layout(ofRevision: "0009-missing", in: entry.id) }
        #expect(!stored.hasEditsSinceLastRevision)
        let meta = try #require(await library.location(of: entry.id)).appending(path: "meta.json")
        let staleMeta = try Data(contentsOf: meta)
        try await library.save(layout, to: entry.id)
        #expect(try await library.load(entry.id).hasEditsSinceLastRevision)
        try staleMeta.write(to: meta)  // as if meta.json's write had failed after layout.json's
        #expect(try await library.load(entry.id).hasEditsSinceLastRevision, "layout.json counts, not meta.json's cached hash")
    }

    /// One Character can be dozens of UTF-16 units; the folder name must still fit APFS's 255.
    @Test func titlesOfLongCharactersStillGetAFolder() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        var titled = layout
        titled.title = String(repeating: "👨‍👩‍👧‍👦", count: 30)
        let entry = try await library.create(titled, origin: .local, firstRevision: nil)
        try await library.rename(entry.id, to: String(repeating: "a\u{301}\u{302}\u{303}\u{304}\u{305}\u{306}\u{307}\u{308}", count: 60))
        #expect(try await library.load(entry.id).layout.title.count == 60)
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
        #expect(try await !library.load(copy.id).hasEditsSinceLastRevision, "the copy opens unedited")
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
            of: "\"formatVersion\" : 1", with: "\"formatVersion\" : 3")
        try text.write(to: meta, atomically: true, encoding: .utf8)
        await #expect(throws: LibraryError.newerFormat(3)) { try await library.load(entry.id) }
    }

    /// Only a package with macro drafts is format 2, so older builds refuse it rather than drop the drafts at their next
    /// save; every other package stays format 1 (ADR 0042). It stays 2: revisions saved since may hold drafts.
    @Test func macroDraftsMakeAPackageFormat2() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let entry = try await library.create(layout, origin: .local, firstRevision: RevisionDraft(source: .import, layout: layout))
        let folder = try #require(await library.location(of: entry.id))
        func version(_ folder: URL) throws -> Int? {
            let meta = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appending(path: "meta.json"))) as? [String: Any]
            return meta?["formatVersion"] as? Int
        }
        #expect(try version(folder) == 1)
        #expect(try !String(contentsOf: folder.appending(path: "layout.json"), encoding: .utf8).contains("macroDrafts"))

        var drafted = layout
        drafted.addMacroDraft(Macro(name: "Sig", steps: [MacroStep(code: "KC_S", delay: 20)]))
        try await library.save(drafted, to: entry.id)
        #expect(try version(folder) == 2)
        #expect(try await library.load(entry.id).layout == drafted)
        try await library.save(layout, to: entry.id)
        #expect(try version(folder) == 2)

        // The version rises before the drafts are written: a failed write leaves no drafts under format 1.
        let other = try await library.create(layout, origin: .local, firstRevision: nil)
        let otherFolder = try #require(await library.location(of: other.id))
        try FileManager.default.removeItem(at: otherFolder.appending(path: "layout.json"))
        try FileManager.default.createDirectory(at: otherFolder.appending(path: "layout.json/blocked"), withIntermediateDirectories: true)
        await #expect(throws: LibraryError.self) { try await library.save(drafted, to: other.id) }
        #expect(try version(otherFolder) == 2)

        let plainCopy = try await library.duplicate(entry.id)
        #expect(try version(#require(await library.location(of: plainCopy.id))) == 1)
        try await library.save(drafted, to: entry.id)
        let draftedCopy = try await library.duplicate(entry.id)
        #expect(try version(#require(await library.location(of: draftedCopy.id))) == 2)
        #expect(try await library.load(draftedCopy.id).layout.macroDrafts == drafted.macroDrafts)
    }

    /// A layout without drafts encodes as before, so no content hash moves: not the "Edited" baseline, not the match
    /// against Oryx's build. These are the hashes main computed before drafts existed.
    @Test func contentHashesOfEveryFixtureAreUnchanged() throws {
        let examples = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "docs/research/oryx-examples")
        let expected = [
            "my-layout-KlgM7-40xJ7M.json": "455113c008a65dda79158c160e6a4969db7da70611d810b212a7ffab7e9c9ff3",
            "my-layout-KlgM7-full.json": "7f6d8a63961d5eb28c437a6c1d5b3c82461c6fbaafa8a2fe9f2a6d0b91dc2953",
            "voyager-default.json": "d2a10b45821b34bb947c58207fb2eed7225542c7f6f49b8584f1d13bb15ebc9e",
            "voyager-e5Rrr.json": "a497cef149a0a79b3143079dc15caab2e176c42e5bfe555c15c25de7a564a5d3",
            "voyager-JRGQm.json": "5836b1d4eafe163dd3f7de206bf39da07f9393c247c0b007e3bfeccc180a18b2",
            "voyager-m9dpx.json": "f064e3bc8d582434f694dfc6f4e897f33a1c9fbc83d8cdeb25bb0106b167297c",
            "voyager-XlrR4.json": "610dbc2fea545fe6cf71e24206a1cba50e7e55fed13960d837b4f73d829a9c5e",
        ]
        // Other people's samples are kept out of the repo, at the same path under `$SEXTANT_REFERENCE`.
        let reference = ProcessInfo.processInfo.environment["SEXTANT_REFERENCE"]
            .map { URL(fileURLWithPath: $0).appending(path: "docs/research/oryx-examples") }
            .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
        for (file, hash) in expected {
            let own = examples.appending(path: file)
            guard let url = FileManager.default.fileExists(atPath: own.path) ? own : reference?.appending(path: file) else { continue }
            let fixture = try KeyboardLayout(oryxJSON: Data(contentsOf: url))
            #expect(try PackageLibrary.contentHash(fixture) == "sha256:\(hash)", "\(file)")
        }
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

    @Test func keepsARecoveryCopyUntilASaveOvertakesIt() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let entry = try await library.create(layout, origin: .local, firstRevision: nil)
        var edited = layout
        edited.updateKey(layer: 0, index: 1) { $0 = Key("KC_Q") }
        try await library.saveRecovery(edited, for: entry.id)
        #expect(await library.recovery(of: entry.id) == edited, "newer than layout.json")
        #expect(try await library.entries().map(\.id) == [entry.id], "the recovery folder is not a layout")

        try await library.save(edited, to: entry.id)
        #expect(await library.recovery(of: entry.id) == nil, "older than the save that followed it")
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: ".recovery/\(entry.id.uuidString).json").path))

        try await library.saveRecovery(edited, for: entry.id)
        try await library.trash(entry.id)
        #expect(await library.recovery(of: entry.id) == nil, "trashing a layout drops its copy")
    }

    /// Renaming a layout no window has open rewrites layout.json; the edits only its recovery copy holds survive it.
    @MainActor @Test func renamingAClosedLayoutKeepsItsRecoveryCopy() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let entry = try await library.create(layout, origin: .local, firstRevision: nil)
        var edited = layout
        edited.updateKey(layer: 0, index: 13) { $0 = Key("KC_Q") }
        try await library.saveRecovery(edited, for: entry.id)
        let app = Library(store: library)
        await app.rename(entry.id, to: "Work")
        let session = try await app.open(entry.id)
        #expect(session.recoveredUnsavedChanges && session.layout.title == "Work")
        #expect(session.layout.key(layer: 0, index: 13) == edited.key(layer: 0, index: 13))
    }

    @Test func keepsAnUnreadableRecoveryCopy() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let entry = try await library.create(layout, origin: .local, firstRevision: nil)
        let file = root.appending(path: ".recovery/\(entry.id.uuidString).json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{".utf8).write(to: file)
        #expect(await library.recovery(of: entry.id) == nil)
        #expect(FileManager.default.fileExists(atPath: file.path), "it may be the only copy of those edits")
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

    // MARK: App Layers (ADR 0054)

    /// The rules live in `app-layers.json` beside the layout: a package without one reads as no rules, and saving them
    /// moves nothing the layout's identity rests on (its content hash, modification date, revisions, Edited state and sx-
    /// fingerprint).
    @Test func appLayersLiveBesideTheLayout() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let entry = try await library.create(layout, origin: .local, firstRevision: RevisionDraft(source: .save, layout: layout))
        #expect(try await library.appLayerRules(of: entry.id) == AppLayerRules(), "a missing file reads as empty")
        let before = try await library.load(entry.id)
        let folder = try #require(await library.location(of: entry.id))
        let metaBefore = try Data(contentsOf: folder.appending(path: "meta.json"))
        let layoutBefore = try Data(contentsOf: folder.appending(path: "layout.json"))

        let rules = AppLayerRules(
            isOn: true,
            rules: [
                AppLayerRule(bundleID: "com.apple.dt.Xcode", name: "Xcode", layerID: layout.layers[1].id),
                AppLayerRule(
                    bundleID: "com.apple.Safari", name: "Safari", layerID: layout.layers[2].id, leaving: .stay, isEnabled: false),
            ])
        try await library.saveAppLayerRules(rules, for: entry.id)
        #expect(try await library.appLayerRules(of: entry.id) == rules)
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "app-layers.json").path))

        let after = try await library.load(entry.id)
        #expect(after.contentHash == before.contentHash && after.entry == before.entry && after.revisions == before.revisions)
        #expect(!after.hasEditsSinceLastRevision, "not Edited")
        #expect(try Data(contentsOf: folder.appending(path: "meta.json")) == metaBefore, "the modification date stays")
        #expect(try Data(contentsOf: folder.appending(path: "layout.json")) == layoutBefore)
        let identity = { (stored: StoredLayout) in FirmwareIdentity(layout: stored.layout, libraryID: entry.id, importedLayout: nil) }
        #expect(identity(after).serial == identity(before).serial, "the sx- fingerprint stays")
    }

    @Test func duplicateCopiesAppLayersAndTrashTakesThem() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let entry = try await library.create(layout, origin: .local, firstRevision: nil)
        let rules = AppLayerRules(
            isOn: true, rules: [AppLayerRule(bundleID: "com.apple.Terminal", name: "Terminal", layerID: layout.layers[2].id)])
        try await library.saveAppLayerRules(rules, for: entry.id)
        let copy = try await library.duplicate(entry.id)
        #expect(try await library.appLayerRules(of: copy.id) == rules)
        // Each package has its own from then on.
        try await library.saveAppLayerRules(AppLayerRules(), for: copy.id)
        #expect(try await library.appLayerRules(of: entry.id) == rules)
        // A copy of a layout without rules gets no file.
        let plain = try await library.create(layout, origin: .local, firstRevision: nil)
        let plainCopy = try await library.duplicate(plain.id)
        let copyFolder = try #require(await library.location(of: plainCopy.id))
        #expect(!FileManager.default.fileExists(atPath: copyFolder.appending(path: "app-layers.json").path))
        try await library.trash(entry.id)
        await #expect(throws: LibraryError.notFound(entry.id)) { try await library.appLayerRules(of: entry.id) }
    }

    @Test func refusesNewerAppLayersAndDamagedOnes() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let entry = try await library.create(layout, origin: .local, firstRevision: nil)
        let file = try #require(await library.location(of: entry.id)).appending(path: "app-layers.json")
        try Data(#"{"formatVersion": 2, "isOn": true, "rules": []}"#.utf8).write(to: file)
        await #expect(throws: LibraryError.newerFormat(2)) { try await library.appLayerRules(of: entry.id) }
        // Duplicating still works; the copy has no rules rather than a newer Sextant's.
        let copy = try await library.duplicate(entry.id)
        #expect(try await library.appLayerRules(of: copy.id) == AppLayerRules())
        try Data("{".utf8).write(to: file)
        await #expect(throws: LibraryError.self) { try await library.appLayerRules(of: entry.id) }
    }
}
