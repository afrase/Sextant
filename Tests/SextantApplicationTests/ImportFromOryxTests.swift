import Foundation
import SextantDomain
import Testing

@testable import SextantApplication

@MainActor
struct ImportFromOryxTests {
    static let link = "https://configure.zsa.io/voyager/layouts/KlgM7/40xJ7M/0"
    let layout: KeyboardLayout
    let store = InMemoryLibrary()
    let library: Library

    init() throws {
        layout = try KeyboardLayout(oryxJSON: Fixtures.userLayoutData)
        library = Library(store: store)
    }

    func model(_ oryx: FakeOryx, input: String = link) -> ImportFromOryx {
        let model = ImportFromOryx(oryx: oryx, library: library)
        model.input = input
        return model
    }

    // MARK: Input

    @Test func validatesTheLinkLive() {
        let model = model(FakeOryx(layout: .success(layout)), input: "not a link")
        #expect(model.reference == nil && model.tokens.isEmpty)
        model.input = Self.link
        #expect(model.reference?.layoutID == "KlgM7")
        #expect(model.tokens.map(\.label) == ["Board", "Layout", "Revision", "Layer"])
        #expect(model.tokens.map(\.value) == ["ZSA Voyager", "KlgM7", "40xJ7M", "0"])
        model.input = "KlgM7"
        #expect(model.tokens.map(\.value) == ["KlgM7", "Latest"])
    }

    @Test func junkInputFailsTheFirstStepWithoutAsking() async {
        let oryx = FakeOryx(layout: .success(layout))
        let model = model(oryx, input: "?")
        await model.fetch()
        #expect(model.steps == [.readLink: .failed])
        #expect(await oryx.layoutRequests.isEmpty)
    }

    // MARK: Preview

    @Test func previewsTheUserLayout() async throws {
        let oryx = FakeOryx(layout: .success(layout))
        let model = model(oryx)
        await model.fetch()
        #expect(model.steps == [.readLink: .done, .fetchLayout: .done, .checkFirmware: .done, .convert: .done])
        #expect(model.error == nil)
        let preview = try #require(model.preview)
        #expect(preview.layout.title == "My MacOS Layout")
        #expect(preview.summary == ImportSummary(layout))
        #expect(preview.existing == nil)
        #expect(preview.notes == ["4 custom labels are shown in Sextant only.", "Oryx stays read-only. Sextant keeps its own copy."])
        #expect(await oryx.layoutRequests == [OryxReference(Self.link)])
        #expect(await oryx.firmwareRequests == ["40xJ7M 4d59bb3dba601672ecefd27e2641561c"])
    }

    @Test func notesUnknownCodes() async throws {
        var future = layout
        future.updateKey(layer: 0, index: 1) { $0 = Key("KC_FUTURE_KEY") }
        let model = model(FakeOryx(layout: .success(future)))
        await model.fetch()
        #expect(model.preview?.notes.first == "1 keys use codes Sextant doesn't know yet. They're kept as they are and marked.")
    }

    @Test func notesTheNavigator() async throws {
        let model = model(FakeOryx(layout: .success(try KeyboardLayout(oryxJSON: Fixtures.data("my-layout-KlgM7-full.json")))))
        await model.fetch()
        #expect(model.preview?.notes.contains("Navigator trackpad found on the right half; its settings come along.") == true)
    }

    @Test(arguments: [OryxError.offline, .notFound, .otherBoard("moonlander"), .unreadable("x"), .server("HTTP 500")])
    func showsWhyTheFetchFailed(_ error: OryxError) async {
        let model = model(FakeOryx(layout: .failure(error)))
        await model.fetch()
        #expect(model.error == error)
        #expect(model.steps == [.readLink: .done, .fetchLayout: .failed])
        #expect(model.preview == nil)
    }

    @Test func theSpecCopyForFetchErrors() {
        #expect(OryxError.offline.localizedDescription == "Sextant couldn't reach Oryx. Check your connection and try again.")
        #expect(
            OryxError.notFound.localizedDescription
                == "This layout is private or doesn't exist. Sextant can only import public layouts.")
        #expect(
            OryxError.otherBoard("moonlander").localizedDescription
                == "This is a Moonlander layout. Sextant supports the ZSA Voyager for now.")
    }

    @Test func aChecksumMismatchIsANoteNotAFailure() async throws {
        let model = model(FakeOryx(layout: .success(layout), firmware: .failure(.checksumMismatch)))
        await model.fetch()
        #expect(model.steps[.checkFirmware] == .warning)
        #expect(model.steps[.convert] == .done)
        #expect(
            model.preview?.notes.first
                == "Oryx's firmware didn't match its checksum, so Sextant didn't keep it. The layout imported fine.")
        let imported = try #require(try await model.importLayout())
        #expect(try await store.firmware(revisionID: "40xJ7M", of: imported.id) == nil)
    }

    @Test func otherFirmwareFailuresAreNotesToo() async {
        let model = model(FakeOryx(layout: .success(layout), firmware: .failure(.offline)))
        await model.fetch()
        #expect(model.steps[.checkFirmware] == .warning)
        #expect(model.preview?.notes.first?.hasPrefix("Sextant couldn't download Oryx's firmware") == true)
    }

    @Test func aDraftRevisionHasNoFirmwareToCheck() async {
        var draft = layout
        draft.oryx?.md5 = nil
        let oryx = FakeOryx(layout: .success(draft))
        let model = model(oryx)
        await model.fetch()
        #expect(model.steps[.checkFirmware] == .done)
        #expect(await oryx.firmwareRequests.isEmpty)
    }

    @Test func editingTheInputDiscardsTheResult() async {
        let model = model(FakeOryx(layout: .success(layout)))
        await model.fetch()
        #expect(model.preview != nil)
        model.input = "KlgM7/other1"
        #expect(model.preview == nil && model.steps.isEmpty)
    }

    @Test func aFetchThatOutlivesItsInputIsDropped() async {
        let oryx = FakeOryx(layout: .success(layout))
        let model = model(oryx)
        await oryx.beforeReply { await MainActor.run { model.input = "KlgM7/other1" } }
        await model.fetch()
        #expect(model.preview == nil && model.error == nil && model.steps.isEmpty)
    }

    // MARK: Saving

    @Test func importsAsANewLayoutWithOryxsFirmware() async throws {
        let model = model(FakeOryx(layout: .success(layout), firmware: .success(Data([0xF0]))))
        #expect(try await model.importLayout() == nil, "nothing to import before a preview")
        await model.fetch()
        model.openAfterImporting = false
        let imported = try #require(try await model.importLayout())
        #expect(!imported.open)
        let stored = try await store.load(imported.id)
        #expect(stored.entry.title == "My MacOS Layout")
        #expect(stored.entry.origin == .oryx(layoutId: "KlgM7", revisionId: "40xJ7M"))
        #expect(stored.revisions.map(\.source) == [.import])
        let firmware = try #require(try await store.firmware(revisionID: "40xJ7M", of: imported.id))
        #expect(firmware.data == Data([0xF0]) && firmware.md5 == "4d59bb3dba601672ecefd27e2641561c")
        #expect(library.entries.map(\.id) == [imported.id])
    }

    @Test func aPreviewIsImportedOnce() async throws {
        let model = model(FakeOryx(layout: .success(layout)))
        await model.fetch()
        async let first = model.importLayout()
        async let second = model.importLayout()
        let results = try await [first, second]
        #expect(results.compactMap(\.self).count == 1, "a double click imports one layout")
        #expect(library.entries.count == 1)
        #expect(model.preview == nil)
    }

    @Test func addsARevisionOfTheLayoutImportedBefore() async throws {
        let entry = try await library.add(imported: layout)
        await library.rename(entry.id, to: "Work")
        let before = try await store.load(entry.id).layout
        var newer = layout
        newer.oryx?.revisionId = "N3wRev"
        newer.oryx?.md5 = "0123456789abcdef0123456789abcdef"
        newer.updateKey(layer: 0, index: 1) { $0 = Key("KC_Q") }

        let model = model(FakeOryx(layout: .success(newer)), input: "KlgM7")
        await model.fetch()
        #expect(model.preview?.existing?.id == entry.id)
        let imported = try #require(try await model.importLayout(asRevision: true))
        #expect(imported.id == entry.id && imported.open)

        var expected = newer
        expected.title = "Work"
        #expect(await store.layout(entry.id) == expected, "the working copy is the import, under the library's title")
        let item = try #require(await store.items[entry.id])
        #expect(item.revisions.map(\.source) == [.import, .save, .import])
        #expect(item.revisionLayouts[item.revisions[1].id] == before, "the replaced working copy is checkpointed")
        #expect(item.firmware["N3wRev"]?.md5 == "0123456789abcdef0123456789abcdef")
        #expect(item.entry.origin == .oryx(layoutId: "KlgM7", revisionId: "N3wRev"))
        #expect(library.entries.count == 1)
    }

    @Test func aNewerRevisionWithoutLocalEditsAddsOnlyTheImport() async throws {
        let entry = try await library.add(imported: layout)
        var newer = layout
        newer.oryx?.revisionId = "N3wRev"
        let model = model(FakeOryx(layout: .success(newer)), input: "KlgM7")
        await model.fetch()
        _ = try await model.importLayout(asRevision: true)
        #expect(await store.items[entry.id]?.revisions.map(\.source) == [.import, .import])
    }

    @Test func addingARevisionOfAnOpenLayoutGoesThroughItsDocument() async throws {
        let entry = try await library.add(imported: layout)
        let session = try await library.open(entry.id, autosaveDelay: .milliseconds(1))
        let undo = UndoManager()
        undo.groupsByEvent = false
        session.undoManager = undo
        var newer = layout
        newer.oryx?.revisionId = "N3wRev"
        newer.updateKey(layer: 0, index: 1) { $0 = Key("KC_Q") }
        let model = model(FakeOryx(layout: .success(newer)), input: "KlgM7")
        await model.fetch()
        let before = session.layout

        undo.beginUndoGrouping()
        _ = try await model.importLayout(asRevision: true)
        undo.endUndoGrouping()
        #expect(session.layout.key(layer: 0, index: 1)?.tap?.code == "KC_Q" && session.layout.title == before.title)
        #expect(session.origin == .oryx(layoutId: "KlgM7", revisionId: "N3wRev"))
        #expect(session.revisions.map(\.source) == [.import, .import])
        #expect(undo.undoActionName == "Import from Oryx")
        #expect(!session.isEditedSinceRevision, "the import is the new last revision")

        session.select(key: 2)
        undo.beginUndoGrouping()
        session.setCode("KC_Z")
        undo.endUndoGrouping()
        await session.flush()
        let stored = try await store.load(entry.id)
        #expect(stored.layout == session.layout, "the next autosave keeps the import")
        #expect(stored.layout.key(layer: 0, index: 1)?.tap?.code == "KC_Q")
        #expect(stored.entry.origin == .oryx(layoutId: "KlgM7", revisionId: "N3wRev"))

        undo.undo()
        undo.undo()
        #expect(session.layout == before, "the import is undoable")
        #expect(session.isEditedSinceRevision, "undone, the layout differs from the import revision")
        #expect(session.origin == .oryx(layoutId: "KlgM7", revisionId: "40xJ7M"))
    }

    @Test func reimportingAnUnchangedLayoutAddsOnlyTheImport() async throws {
        let entry = try await library.add(imported: layout)
        let model = model(FakeOryx(layout: .success(layout)))
        await model.fetch()
        _ = try await model.importLayout(asRevision: true)
        #expect(await store.items[entry.id]?.revisions.map(\.source) == [.import, .import])
    }

    @Test func addingARevisionOfADeletedLayoutFails() async throws {
        let entry = try await library.add(imported: layout)
        let model = model(FakeOryx(layout: .success(layout)))
        await model.fetch()
        await library.trash(entry.id)
        await #expect(throws: LibraryError.notFound(entry.id)) { try await model.importLayout(asRevision: true) }
        #expect(model.preview != nil, "a failed save keeps the preview for another try")
    }

    /// With no window open, Add as Revision uses a temporary session; a failed working-copy write must surface.
    @Test func aFailedWorkingCopyWriteIsReported() async throws {
        let entry = try await library.add(imported: layout)
        var newer = layout
        newer.updateKey(layer: 0, index: 1) { $0 = Key("KC_Q") }
        let model = model(FakeOryx(layout: .success(newer)))
        await model.fetch()
        await store.failSaves(with: .io("disk full"))
        await #expect(throws: LibraryError.io("disk full")) { try await model.importLayout(asRevision: true) }
        #expect(model.preview != nil, "a failed save keeps the preview for another try")
        await store.failSaves(with: nil)
        #expect(
            await store.items[entry.id]?.layout.key(layer: 0, index: 1) == layout.key(layer: 0, index: 1), "the working copy is unchanged")
    }

    @Test func aFailedSaveAfterTheInputChangedDropsThePreview() async throws {
        let entry = try await library.add(imported: layout)
        let model = model(FakeOryx(layout: .success(layout)))
        await model.fetch()
        await library.trash(entry.id)
        await store.beforeLoad { await MainActor.run { model.input = "KlgM7/other1" } }
        await #expect(throws: LibraryError.notFound(entry.id)) { try await model.importLayout(asRevision: true) }
        #expect(model.preview == nil, "the preview belonged to the old input")
    }
}

/// A scripted `OryxReader` that records what it was asked for.
actor FakeOryx: OryxReader {
    private let layoutResult: Result<KeyboardLayout, OryxError>
    private let firmwareResult: Result<Data, OryxError>
    private var hook: (@Sendable () async -> Void)?
    private(set) var layoutRequests: [OryxReference] = []
    /// `"<revision> <md5>"` per request.
    private(set) var firmwareRequests: [String] = []

    init(layout: Result<KeyboardLayout, OryxError>, firmware: Result<Data, OryxError> = .success(Data([1]))) {
        layoutResult = layout
        firmwareResult = firmware
    }

    /// Runs `body` while a layout request is in flight.
    func beforeReply(_ body: @escaping @Sendable () async -> Void) { hook = body }

    func layout(_ reference: OryxReference) async throws(OryxError) -> KeyboardLayout {
        layoutRequests.append(reference)
        await hook?()
        return try layoutResult.get()
    }

    func firmware(revisionID: String, expectedMD5: String) throws(OryxError) -> Data {
        firmwareRequests.append("\(revisionID) \(expectedMD5)")
        return try firmwareResult.get()
    }
}
