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
        #expect(serial.hasPrefix("sx:1F3A9C2B:") && serial.count == 20, "\(serial)")
        #expect(!serial.contains("/"), "Oryx-reading tools must not take it for an Oryx serial")
        #expect(FirmwareIdentity(layout: edited, libraryID: id, importedLayout: layout).serial == serial, "same content, same serial")
        #expect(FirmwareIdentity(layout: layout, libraryID: id, importedLayout: nil).serial != serial, "content changes it")
        #expect(FirmwareIdentity(layout: layout, libraryID: id, importedLayout: nil).serial.hasPrefix("sx:"), "no baseline, no Oryx serial")
    }

    @Test func serialsMatchByContentThenByLayout() {
        let oryx = FirmwareIdentity(serial: "KlgM7/40xJ7M")
        let ours = FirmwareIdentity(serial: "sx:1F3A9C2B:00000001")
        func match(_ serial: String, _ expected: FirmwareIdentity) -> FirmwareMatch {
            FirmwareMatch(serial: serial, expected: expected, libraryID: id, oryxLayoutID: "KlgM7")
        }
        #expect(match("KlgM7/40xJ7M", oryx) == .current)
        #expect(match("KlgM7/aaaaaa", oryx) == .thisLayout, "another Oryx revision of this layout")
        #expect(match("KlgM7/40xJ7M", ours) == .thisLayout, "Oryx's build from before the edits")
        #expect(match("sx:1F3A9C2B:00000002", ours) == .thisLayout, "an older Sextant build")
        #expect(match("sx:1F3A9C2B:00000001", ours) == .current)
        #expect(match("Q9x2/aa11", ours) == .otherLayout)
        #expect(match("sx:00000000:00000001", ours) == .otherLayout)
        #expect(match("default/latest", oryx) == .otherLayout)
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
