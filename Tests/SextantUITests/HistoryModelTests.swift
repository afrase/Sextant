import Foundation
import SextantApplication
import SextantDomain
import Testing

@testable import SextantUI

/// The History page's model (spec §8.7, ADR 0043) over revisions of the user's layout.
@MainActor
struct HistoryModelTests {
    let layout: KeyboardLayout

    init() throws { layout = try KeyboardLayout(oryxJSON: #require(userLayoutData)) }

    /// A session whose revisions are `revisions`, oldest first; the working copy is the newest.
    func history(_ revisions: [KeyboardLayout]) async -> HistoryModel {
        let library = RevisionLibrary(revisions)
        let stored = await library.stored
        let model = HistoryModel(session: EditSession(stored: stored, library: library), onKeyboard: nil)
        await model.load()
        return model
    }

    /// Revision 2 edits key 1 on Main and adds a key on Sym+Num.
    func edited() throws -> KeyboardLayout {
        var edited = layout
        edited.updateKey(layer: 0, index: 1) { $0 = Key("KC_F13") }
        let transparent = try #require(layout.layers[1].keys.firstIndex { $0.isTransparent })
        edited.updateKey(layer: 1, index: transparent) { $0 = Key("KC_F14") }
        return edited
    }

    @Test func theNewestIsSelectedAndComparedWithItsParent() async throws {
        let history = await history([layout, try edited()])
        #expect(history.selected?.number == 2 && history.comparison == .parent)
        #expect(history.base(.parent) == layout)
        #expect(history.shown?.changes?.diff.keyChanges.count == 2)
        #expect(history.canCompare(with: .current))
        #expect(!history.canCompare(with: .onKeyboard), "no keyboard runs this layout")

        history.selectedID = history.session.revisions.first?.id
        #expect(!history.canCompare(with: .parent), "the first revision has no parent")
        #expect(history.shown?.changes == nil)
        #expect(history.decoration(layer: 0, index: 1) == CapDecoration(), "nothing to compare: plain caps")
    }

    @Test func capsShowWhatChangedAndUnchangedKeysAreQuiet() async throws {
        let history = await history([layout, try edited()])
        let changed = history.decoration(layer: 0, index: 1)
        #expect(changed.badge?.symbol == "circle.fill" && changed.ring == Tokens.warning)
        #expect(history.decoration(layer: 0, index: 2).opacity == 0.4)
        let added = try #require(layout.layers[1].keys.firstIndex { $0.isTransparent })
        #expect(history.decoration(layer: 1, index: added).badge?.symbol == "plus.circle.fill")

        // Compared with Current, the board's keys read the other way: the key revision 2 added is one revision 1 lacks.
        history.selectedID = history.session.revisions.first?.id
        history.comparison = .current
        #expect(history.decoration(layer: 1, index: added).badge?.symbol == "minus.circle.fill")
    }

    @Test func theSuggestedMessageSaysWhatChanged() throws {
        var oneLayer = layout
        for index in 0..<5 { oneLayer.updateKey(layer: 2, index: index) { $0 = Key("KC_F\(index + 13)") } }
        #expect(HistoryModel.message(for: oneLayer.changes(from: layout), in: oneLayer) == "Edited 5 keys on Brd+Sys")

        var threeLayers = layout
        for (layer, indices) in [0: 0..<4, 1: 0..<4, 2: 0..<4] {
            for index in indices { threeLayers.updateKey(layer: layer, index: index) { $0 = Key("KC_F\(index + 13)") } }
        }
        #expect(HistoryModel.message(for: threeLayers.changes(from: layout), in: threeLayers) == "Edited 12 keys on 3 layers")

        var settings = layout
        settings.settings["tappingTerm"] = .number(180)
        settings.settings["flowTap"] = .number(100)
        #expect(HistoryModel.message(for: settings.changes(from: layout), in: settings) == "Changed 2 settings")

        var renamed = layout
        renamed.title = "Work"
        #expect(HistoryModel.message(for: renamed.changes(from: layout), in: renamed) == "Renamed the layout")
    }

    @Test func saveRevisionOpensWithTheSuggestionAndOnlyWhenEdited() async throws {
        let history = await history([layout])
        await history.beginSave()
        #expect(history.saveMessage == nil, "nothing changed since the last revision")
        history.session.setCode("KC_F13", layer: 0, index: 1)
        await history.beginSave()
        #expect(history.saveMessage == "Edited 1 key on Main")
        try await history.save(message: "  ")
        #expect(history.saveMessage == nil && history.session.revisions.count == 2)
        #expect(history.session.revisions.last?.message == nil, "a blank message stores none")
    }

    /// The suggestion needs only the last revision, so ⌘S doesn't wait on the whole History.
    @Test func saveRevisionReadsOnlyTheLastRevision() async throws {
        let library = RevisionLibrary([layout, try edited(), layout])
        let history = HistoryModel(session: EditSession(stored: await library.stored, library: library), onKeyboard: nil)
        history.session.setCode("KC_F13", layer: 0, index: 1)
        await history.beginSave()
        #expect(history.saveMessage == "Edited 1 key on Main")
        #expect(await library.reads == 1)
    }

    @Test func aRevisionIsNeverComparedWithItself() async throws {
        let history = await history([layout, try edited()])
        let first = try #require(history.session.revisions.first)
        history.comparison = .revision(first.id)
        #expect(history.shown?.changes?.diff.keyChanges.count == 2)
        history.selectedID = first.id
        #expect(history.comparison == .parent)
    }

    @Test func restoreRunsOnceAndSelectsTheNewRevision() async throws {
        let history = await history([layout, try edited()])
        let first = try #require(history.session.revisions.first)
        #expect(!history.canRestore(try #require(history.session.revisions.last)), "the document is the newest already")
        #expect(history.canRestore(first))
        history.selectedID = first.id
        // A double click: the second restore starts while the first waits on the library.
        async let click: Void = history.restore(first)
        async let again: Void = history.restore(first)
        _ = await (click, again)
        #expect(history.session.revisions.map(\.message) == [nil, nil, "Restored revision 1"])
        #expect(history.session.layout == layout && history.selected?.number == 3 && !history.canRestore(first))

        let missing = RevisionSummary(id: "missing", number: 9, createdAt: .now, source: .save, message: nil, contentHash: "")
        await history.restore(missing)
        #expect(history.error == .notFound(history.session.id))
    }

    /// ON KEYBOARD and the On keyboard comparison name the keyboard's revision, in that layout's window only.
    @Test func onKeyboardIsTheKeyboardsRevisionOfThisLayoutOnly() async throws {
        let oryx = try #require(layout.oryx)
        let library = RevisionLibrary([layout, try edited()], origin: .oryx(layoutId: oryx.layoutId, revisionId: oryx.revisionId))
        let shared = Library(store: library)
        await shared.refresh()
        let keyboard = PluggedIn(serial: oryx.serial)
        let live = LiveSession(watcher: keyboard, link: keyboard, secureInputProbe: { false })
        live.start()
        let onKeyboard = OnKeyboard(library: shared, store: library, live: live)
        onKeyboard.start()
        for _ in 0..<200 where onKeyboard.running == nil { try await Task.sleep(for: .milliseconds(10)) }

        let history = HistoryModel(session: EditSession(stored: await library.stored, library: library), onKeyboard: onKeyboard)
        await history.load()
        #expect(history.running?.revision?.number == 1, "Oryx's build is the import revision")
        #expect(history.canCompare(with: .onKeyboard) && history.base(.onKeyboard) == layout)
        history.comparison = .onKeyboard
        #expect(history.shown?.changes?.diff.keyChanges.count == 2)

        var other = await library.stored
        other.entry = LibraryEntry(id: UUID(), title: "Other", origin: .local, modifiedAt: Date())
        let elsewhere = HistoryModel(session: EditSession(stored: other, library: library), onKeyboard: onKeyboard)
        #expect(elsewhere.running == nil && !elsewhere.canCompare(with: .onKeyboard), "another layout's window")
    }

    /// The palette's Documents rows open History on a revision; Save Revision… is a command once there is something to save.
    @Test func thePaletteShowsRevisionsAndSavesThem() async throws {
        let model = try await openUserLayout()
        model.openPalette(query: "save revision")
        #expect(!model.paletteItems.contains { $0.id == "command-Save Revision…" }, "nothing to save")
        model.session?.setCode("KC_F13", layer: 0, index: 1)
        model.openPalette(query: "save revision")
        #expect(model.paletteItems.contains { $0.id == "command-Save Revision…" })

        model.openPalette(query: "revision 1")
        model.run(try #require(model.paletteItems.first { $0.id == "revision-1" }))
        for _ in 0..<100 where model.history?.selectedID == nil { await Task.yield() }
        #expect(model.palette == nil && model.destination == .history && model.history?.selectedID == "1")
    }

    /// A layer only the revision has can still be shown, until another layer is chosen.
    @Test func layersMatchByIdAndARevisionOnlyLayerCanBeShown() async throws {
        var older = layout
        older.layers.append(.transparent(title: "Games"))
        older.layers.swapAt(1, 2)
        let history = await history([older, layout])
        history.selectedID = history.session.revisions.first?.id
        history.session.select(layer: 1)
        #expect(history.shownLayer(in: older) == 2, "Sym+Num, by id")
        history.show(layer: 3, of: older)
        #expect(history.shownLayer(in: older) == 3 && history.session.selection.layer == 1)
        history.show(layer: 1, of: older)
        #expect(history.session.selection.layer == 2 && history.shownLayer(in: older) == 1, "Brd+Sys is the document's layer 2")
    }

    /// The footer's kind key follows the board, which on History shows the revision's layer (spec §3.7).
    @Test func theKindKeyListsTheShownRevisionLayer() async throws {
        var older = layout
        var games = Layer.transparent(title: "Games")
        games.keys[3] = Key("KC_W")
        older.layers.append(games)
        let library = Library(store: RevisionLibrary([older, layout]))
        await library.refresh()
        let model = LayoutWindowModel(library: library)
        await model.open(nil)
        await model.showRevision("0001-rev")
        model.history?.show(layer: 3, of: older)
        #expect(model.kindsOnLayer == [.regular, .transparent])
    }
}

/// A library holding one layout's revisions, the first an import; only what History reads works.
private actor RevisionLibrary: LayoutLibrary {
    private let entry: LibraryEntry
    private var revisions: [(summary: RevisionSummary, layout: KeyboardLayout)] = []
    private var working: KeyboardLayout
    /// Revision layouts read so far.
    private(set) var reads = 0

    init(_ layouts: [KeyboardLayout], origin: LayoutOrigin = .local) {
        entry = LibraryEntry(id: UUID(), title: "Layout", origin: origin, modifiedAt: Date())
        working = layouts.last ?? KeyboardLayout(title: "", layers: [])
        revisions = layouts.enumerated().map { n, layout in
            (Self.summary(n + 1, layout, source: n == 0 ? .import : .save, message: nil), layout)
        }
    }

    var stored: StoredLayout {
        StoredLayout(entry: entry, layout: working, contentHash: "h\(working.hashValue)", revisions: revisions.map(\.summary))
    }

    private static func summary(_ n: Int, _ layout: KeyboardLayout, source: RevisionSource, message: String?) -> RevisionSummary {
        RevisionSummary(
            id: "000\(n)-rev", number: n, createdAt: Date(), source: source, message: message, contentHash: "h\(layout.hashValue)")
    }

    func entries() -> [LibraryEntry] { [entry] }
    func load(_ id: UUID) -> StoredLayout { stored }
    func create(_ layout: KeyboardLayout, origin: LayoutOrigin, firstRevision: RevisionDraft?) -> LibraryEntry { entry }
    func save(_ layout: KeyboardLayout, to id: UUID) { working = layout }
    func appendRevision(_ draft: RevisionDraft, to id: UUID) -> RevisionSummary {
        let summary = Self.summary(revisions.count + 1, draft.layout, source: draft.source, message: draft.message)
        revisions.append((summary, draft.layout))
        return summary
    }
    func layout(ofRevision revisionID: String, in id: UUID) throws(LibraryError) -> KeyboardLayout {
        reads += 1
        guard let layout = revisions.first(where: { $0.summary.id == revisionID })?.layout else { throw .notFound(id) }
        return layout
    }
    func rename(_ id: UUID, to title: String) {}
    func duplicate(_ id: UUID) throws(LibraryError) -> LibraryEntry { throw .notFound(id) }
    func trash(_ id: UUID) {}
    func storeFirmware(_ data: Data, md5: String, revisionID: String, to id: UUID) {}
    func firmware(revisionID: String, of id: UUID) -> (data: Data, md5: String)? { nil }
    func location(of id: UUID) -> URL? { nil }
    func saveRecovery(_ layout: KeyboardLayout, for id: UUID) {}
    func recovery(of id: UUID) -> KeyboardLayout? { nil }
    func discardRecovery(of id: UUID) {}
    func appLayerRules(of id: UUID) -> AppLayerRules { AppLayerRules() }
    func saveAppLayerRules(_ rules: AppLayerRules, for id: UUID) {}
}

/// A Voyager plugged in with live access off: its serial comes from enumeration, and nothing is read or sent.
private struct PluggedIn: DeviceWatcher, KeyboardLink {
    var serial: String

    func events(for board: BoardDefinition) -> AsyncStream<DeviceEvent> {
        AsyncStream { continuation in
            continuation.yield(.attached(.keyboard(KeyboardDevice(id: 1, productID: 0x1977, serial: serial))))
            continuation.finish()
        }
    }

    func session(with device: KeyboardDevice, board: BoardDefinition, commands: AsyncStream<KeyboardCommand>) -> AsyncStream<LiveEvent> {
        AsyncStream { continuation in
            continuation.yield(.ended(.hardwareAccessOff))
            continuation.finish()
        }
    }
}
