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
    /// A macro draft isn't compiled, so it keeps Oryx's serial and doesn't move a Sextant one.
    @Test func macroDraftsDontChangeTheIdentity() {
        var drafted = layout
        drafted.addMacroDraft()
        #expect(FirmwareIdentity(layout: drafted, libraryID: id, importedLayout: layout).serial == "KlgM7/40xJ7M")
        var edited = layout
        edited.updateKey(layer: 0, index: 1) { $0 = Key("KC_Q") }
        var editedDrafted = edited
        editedDrafted.addMacroDraft()
        #expect(
            FirmwareIdentity(layout: editedDrafted, libraryID: id, importedLayout: drafted)
                == FirmwareIdentity(layout: edited, libraryID: id, importedLayout: layout))
    }

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

    // MARK: Across Macs (ADR 0061)

    /// The fingerprint is the CRC of the JSON the build stores, so a record read back names the serial it came with.
    @Test func theFingerprintIsTheStoredJSONsCRC() {
        var edited = layout
        edited.updateKey(layer: 0, index: 1) { $0 = Key("KC_Q") }
        let fingerprint = String(format: "%08X", FirmwareImage.crc(edited.firmwareJSON()))
        #expect(FirmwareIdentity(layout: edited, libraryID: id, importedLayout: layout).serial == "sx-1F3A9C2B-" + fingerprint)
        #expect(FirmwareIdentity.sextantFingerprint(of: "sx-1F3A9C2B-" + fingerprint) == fingerprint)
        #expect(String(format: "%08X", LayoutRecord(layout: edited, libraryIDs: [id]).fingerprint) == fingerprint)
    }

    @Test func onlySextantSerialsHaveAFingerprint() {
        #expect(FirmwareIdentity.sextantFingerprint(of: "sx-1F3A9C2B-00C0FFEE") == "00C0FFEE")
        #expect(FirmwareIdentity.sextantFingerprint(of: "KlgM7/40xJ7M") == nil)
        #expect(FirmwareIdentity.sextantFingerprint(of: "sx-1F3A9C2B-0000FFEZ") == nil, "not hex")
        #expect(FirmwareIdentity.sextantFingerprint(of: "sx-1F3A9C2B-00C0FFEE-1") == nil)
        #expect(FirmwareIdentity.sextantFingerprint(of: "sx-1F3A9C2-000C0FFEE") == nil)
        #expect(FirmwareIdentity.sextantFingerprint(of: "") == nil)
    }

    /// The same layout imported on two Macs has two library ids; linked, each Mac's builds are the layout's on the other.
    @Test func aliasesNameTheLayoutOnOtherMacs() {
        let otherMac = UUID(uuidString: "0A2B4C6D-0000-4000-8000-000000000000") ?? UUID()
        let entry = LibraryEntry(id: id, title: "", origin: .local, modifiedAt: .now, aliases: [otherMac, id])
        #expect(entry.aliases == [otherMac], "never its own id")
        #expect(entry.isOnKeyboard(serial: "sx-0A2B4C6D-00000001") && entry.isOnKeyboard(serial: "sx-1F3A9C2B-00000001"))
        #expect(!entry.isOnKeyboard(serial: "sx-00000000-00000001"))

        let ours = FirmwareIdentity(serial: "sx-1F3A9C2B-00000001")
        func match(_ serial: String, linked: Bool = true) -> FirmwareMatch {
            FirmwareMatch(serial: serial, expected: ours, libraryID: id, aliases: linked ? [otherMac] : [], oryxLayoutID: nil)
        }
        #expect(match("sx-0A2B4C6D-00000001") == .current, "the same content, flashed from the other Mac")
        #expect(match("sx-0A2B4C6D-00000002") == .thisLayout, "another version, flashed from the other Mac")
        #expect(match("sx-0A2B4C6D-00000001", linked: false) == .otherLayout, "not linked")
        #expect(match("sx-00000000-00000001") == .otherLayout, "another layout with the same content is still another layout")
        #expect(match("sx-1F3A9C2B-00000001") == .current)
    }

    /// History's ON KEYBOARD badge for a build from the other Mac: the flash revision with the same content.
    @Test func aBuildFromAnotherMacNamesTheRevisionWithItsContent() async throws {
        let store = InMemoryLibrary()
        let entry = try await store.create(layout, origin: .local, firstRevision: RevisionDraft(source: .save, layout: layout))
        var edited = layout
        edited.title = "Edited"
        let flash = try await store.appendRevision(RevisionDraft(source: .flash, layout: edited), to: entry.id)
        let revisions = try await store.load(entry.id).revisions
        let otherMac = UUID()
        let serial = FirmwareIdentity(layout: edited, libraryID: otherMac, importedLayout: nil).serial
        func revision(aliases: Set<UUID>) async -> String? {
            await FirmwareIdentity.revision(
                runningSerial: serial, of: entry.id, aliases: aliases, origin: entry.origin, revisions: revisions, library: store)?
                .summary.id
        }
        #expect(await revision(aliases: [otherMac]) == flash.id)
        #expect(await revision(aliases: []) == nil, "unlinked, it isn't this layout's")
    }

    @Test func theRecordNamesTheLayoutsOwnIdFirstThenItsAliases() {
        let (a, b) = (UUID(), UUID())
        let plain = FirmwareIdentity(layout: layout, libraryID: id, importedLayout: layout)
        let stored = plain.storingRecord(of: layout, libraryID: id, aliases: [b, a, id])
        #expect(stored.serial == plain.serial)
        #expect(stored.record?.libraryIDs == [id] + [a, b].sorted { $0.uuidString < $1.uuidString })
        #expect(stored.record?.json == layout.firmwareJSON())

        var huge = layout
        // Random text barely compresses: far over the 32 KiB a record may take.
        huge.title = (0..<3000).map { _ in UUID().uuidString }.joined()
        #expect(plain.storingRecord(of: huge, libraryID: id, aliases: []).record == nil, "too large: built without one")
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
