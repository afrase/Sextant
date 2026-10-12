import Foundation
import SextantApplication
import SextantDomain
import Testing

struct FirmwareIdentityTests {
    let layout: KeyboardLayout
    let id = UUID(uuidString: "1F3A9C2B-0000-4000-8000-000000000000") ?? UUID()

    init() throws { layout = try KeyboardLayout(oryxJSON: Fixtures.userLayoutData) }

    @Test func anUnchangedOryxImportKeepsOryxsSerial() {
        #expect(FirmwareIdentity(layout: layout, libraryID: id, importedLayout: layout).serial == "KlgM7/40xJ7M")
    }

    @Test func anythingElseGetsAStableSextantSerial() throws {
        var edited = layout
        edited.updateKey(layer: 0, index: 1) { $0 = Key("KC_Q") }
        let serial = FirmwareIdentity(layout: edited, libraryID: id, importedLayout: layout).serial
        #expect(serial.hasPrefix("sx-1F3A9C2B-") && serial.count == 20, "\(serial)")
        #expect(!serial.contains("/"), "Oryx-reading tools must not take it for an Oryx serial")
        #expect(serial.wholeMatch(of: /[A-Za-z0-9_-]+/) != nil, "only characters the generator accepts")
        #expect(FirmwareIdentity(layout: edited, libraryID: id, importedLayout: layout).serial == serial, "same content, same serial")
        #expect(FirmwareIdentity(layout: layout, libraryID: id, importedLayout: nil).serial != serial, "content changes it")
        #expect(FirmwareIdentity(layout: layout, libraryID: id, importedLayout: nil).serial.hasPrefix("sx-"), "no baseline, no Oryx serial")
    }

    /// The sidebar's "On keyboard" badge: Oryx's build of the layout's Oryx layout, or any Sextant build of it.
    @Test func anEntryKnowsItsBuildsOnTheKeyboard() {
        let oryx = LibraryEntry(id: id, title: "", origin: .oryx(layoutId: "KlgM7", revisionId: "40xJ7M"), modifiedAt: .now)
        #expect(oryx.isOnKeyboard(serial: "KlgM7/zzzzz") && oryx.isOnKeyboard(serial: "sx-1F3A9C2B-00000001"))
        let local = LibraryEntry(id: UUID(), title: "", origin: .local, modifiedAt: .now)
        #expect(!local.isOnKeyboard(serial: "KlgM7/40xJ7M") && !local.isOnKeyboard(serial: "sx-1F3A9C2B-00000001"))
    }

    @Test func serialsMatchByContentThenByLayout() {
        let oryx = FirmwareIdentity(serial: "KlgM7/40xJ7M")
        let ours = FirmwareIdentity(serial: "sx-1F3A9C2B-00000001")
        func match(_ serial: String, _ expected: FirmwareIdentity) -> FirmwareMatch {
            FirmwareMatch(serial: serial, expected: expected, libraryID: id, oryxLayoutID: "KlgM7")
        }
        #expect(match("KlgM7/40xJ7M", oryx) == .current)
        #expect(match("KlgM7/aaaaaa", oryx) == .thisLayout, "another Oryx revision of this layout")
        #expect(match("KlgM7/40xJ7M", ours) == .thisLayout, "Oryx's build from before the edits")
        #expect(match("sx-1F3A9C2B-00000002", ours) == .thisLayout, "an older Sextant build")
        #expect(match("sx-1F3A9C2B-00000001", ours) == .current)
        #expect(match("Q9x2/aa11", ours) == .otherLayout)
        #expect(match("sx-00000000-00000001", ours) == .otherLayout)
        #expect(match("default/latest", oryx) == .otherLayout)
    }

    /// History's ON KEYBOARD badge.
    @Test func aSerialNamesTheRevisionItWasBuiltFrom() async throws {
        let store = InMemoryLibrary()
        let entry = try await store.create(
            layout, origin: .oryx(layoutId: "KlgM7", revisionId: "40xJ7M"), firstRevision: RevisionDraft(source: .import, layout: layout))
        var edited = layout
        edited.title = "Edited"
        var later = layout
        later.title = "Later"
        for (source, layout) in [(RevisionSource.flash, edited), (.save, edited), (.flash, later)] {
            _ = try await store.appendRevision(RevisionDraft(source: source, layout: layout), to: entry.id)
        }
        let revisions = try await store.load(entry.id).revisions
        func revision(_ serial: String) async -> String? {
            await FirmwareIdentity.revision(
                runningSerial: serial, of: entry.id, origin: entry.origin, revisions: revisions, library: store)?
                .summary.id
        }
        #expect(await revision("KlgM7/40xJ7M") == "1", "the import, not edited revisions that keep its Oryx info")
        let sextant = FirmwareIdentity(layout: edited, libraryID: entry.id, importedLayout: layout).serial
        #expect(await revision(sextant) == "2", "the newest flash with its content, not a save")
        #expect(await revision("KlgM7/zzzzzz") == nil)
        #expect(await revision("sx-\(entry.id.uuidString.prefix(8))-00000000") == nil)
        #expect(await revision("Q9x2/aa11") == nil, "another layout's serial")
    }

    @Test func theBaselineIsTheLatestImportRevision() async throws {
        let store = InMemoryLibrary()
        let entry = try await store.create(layout, origin: .local, firstRevision: RevisionDraft(source: .import, layout: layout))
        var edited = layout
        edited.title = "Edited"
        _ = try await store.appendRevision(RevisionDraft(source: .save, layout: edited), to: entry.id)
        let revisions = try await store.load(entry.id).revisions
        #expect(await FirmwareIdentity.importedLayout(of: entry.id, revisions: revisions, library: store) == layout)
        #expect(await FirmwareIdentity.importedLayout(of: entry.id, revisions: [], library: store) == nil)
        #expect(await FirmwareIdentity.importedLayout(of: UUID(), revisions: revisions, library: store) == nil, "unreadable → nil")
    }
}
