import Foundation
import SextantApplication
import SextantDomain
import Testing

@testable import SextantUI

/// Import from Oryx, layout management and the Firmware Settings page (spec §3.6, §8.1, §8.8).
@MainActor
struct ImportSliceTests {
    struct NoOryx: OryxReader {
        func layout(_ reference: OryxReference) async throws(OryxError) -> KeyboardLayout { throw .offline }
        func firmware(revisionID: String, expectedMD5: String) async throws(OryxError) -> Data { throw .offline }
    }

    /// Import from Connected Keyboard needs an Oryx `layout/revision` serial; Sextant's own builds name no Oryx layout.
    @Test func connectedKeyboardImportNeedsAnOryxSerial() {
        #expect(LayoutWindowModel.oryxSerial("KlgM7/40xJ7M") == "KlgM7/40xJ7M")
        #expect(LayoutWindowModel.oryxSerial("sx-1234ABCD-89ABCDEF") == nil)
        #expect(LayoutWindowModel.oryxSerial("KlgM7") == nil)
        #expect(LayoutWindowModel.oryxSerial(nil) == nil)
    }

    @Test func openImportPrefillsAFreshFlow() async throws {
        let unwired = try await openUserLayout()
        unwired.openImport("KlgM7/40xJ7M")
        #expect(!unwired.canImport && unwired.importFlow == nil, "importing is off where it isn't wired")
        let library = unwired.library
        let model = LayoutWindowModel(library: library, makeImport: { ImportFromOryx(oryx: NoOryx(), library: library) })
        model.openImport("KlgM7/40xJ7M")
        let first = try #require(model.importFlow)
        #expect(model.canImport && first.input == "KlgM7/40xJ7M" && first.reference?.revisionID == "40xJ7M")
        model.openImport()
        #expect(model.importFlow !== first && model.importFlow?.input.isEmpty == true)
    }

    /// Open after importing brings forward another window only when this one can't show the layout itself.
    @Test func importRevealsTheLayoutInTheRightWindow() async throws {
        let model = try await openUserLayout()
        let here = try #require(model.session?.id)
        let other = UUID()
        #expect(model.windowToReveal(other, open: true) == other, "a new layout gets its own window")
        #expect(model.windowToReveal(other, open: false) == nil)
        #expect(model.windowToReveal(here, open: true) == nil, "a revision of the layout shown here")
        let empty = LayoutWindowModel(library: model.library)
        #expect(empty.windowToReveal(other, open: true) == nil, "an empty window opens the newest itself")
        #expect(empty.windowToReveal(here, open: true) == here, "open in another window: that window comes forward")
    }

    /// Until its first load finishes, a window shows a spinner, not "every layout is open in another window".
    @Test func aWindowIsOpeningUntilItsFirstLoadFinishes() async throws {
        let model = try await openUserLayout()
        let second = LayoutWindowModel(library: model.library)
        #expect(second.isOpening && second.library.hasLoaded)
        #expect(await second.open(nil) == nil && !second.isOpening)
    }

    /// Key commands can't reach the key the Firmware Settings page hides; the selection waits for the board.
    @Test func keyCommandsAreOffOnTheFirmwareSettingsPage() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        session.select(layer: 1)
        session.select(key: 19)
        model.showsFirmwareSettings = true
        #expect(!model.hasSelectedKey && !model.canOverrideKey && session.selection.keyIndex == 19)
        model.showIssue(KeyRef(layer: 0, index: 3))
        #expect(!model.showsFirmwareSettings && model.hasSelectedKey, "Show Key returns to the board")
    }

    /// Trashing the layout open here ends its session safely; another window's layout can't be trashed from here.
    @Test func trashingTheOpenLayoutClosesItsSessionFirst() async throws {
        let model = try await openUserLayout()
        let id = try #require(model.session?.id)
        let neighbour = LayoutWindowModel(library: model.library)
        let second = try await model.library.importOryxJSON(try #require(userLayoutData))
        await neighbour.open(second.id)
        #expect(model.canTrash(second.id) && model.canTrash(id), "the dialog closes the other window first")
        await model.trashLayout(second.id)
        #expect(neighbour.session?.id == second.id, "refused while the other window still has it open")
        await model.trashLayout(id)
        #expect(model.session == nil && !model.library.isOpen(id))
    }

    @Test func sidebarTitleFollowsTheOpenDocument() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        session.setTitle("Work")
        #expect(model.title(of: session.id) == "Work" && model.library.entries.first?.title == "My MacOS Layout")
    }

    /// MVP core sections only, filtered to the board, the Navigator kind and the settings they depend on.
    @Test func firmwareSettingsShowTheCoreSections() async throws {
        let layout = try KeyboardLayout(oryxJSON: try #require(userLayoutData))
        let sections = FirmwareSettings.sections(for: layout)
        #expect(sections.map(\.id) == ["debounce", "rgb", "tapping", "oneshot", "navigator"], "Navigator, to attach one")
        #expect(sections.last?.settings.isEmpty == true, "no Navigator, no Navigator settings")
        #expect(sections[1].settings.map(\.id) == ["rgbTimeout"])
        var trackpad = layout
        trackpad.navigator = NavigatorConfig(kind: .trackpad, side: .right)
        let navigator = try #require(FirmwareSettings.sections(for: trackpad).last)
        #expect(navigator.id == "navigator" && !navigator.settings.contains { $0.id == "invertScrollX" }, "trackball only")
        #expect(!navigator.settings.contains { $0.id == "oneShotAutoMouseTimeout" })
        trackpad.navigator?.options["oneShotAutoMouse"] = .bool(true)
        #expect(FirmwareSettings.sections(for: trackpad).last?.settings.contains { $0.id == "oneShotAutoMouseTimeout" } == true)
        let oneShot = try #require(SettingsCatalog.voyager.setting(id: "oneShotTimeout"))
        #expect(FirmwareSettings.onValue(oneShot) == .number(100), "a slider off by default starts at the bottom of its range")
    }
}
