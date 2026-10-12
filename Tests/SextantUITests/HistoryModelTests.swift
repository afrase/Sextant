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
}

/// A library holding one layout's revisions; only what History reads works.
private actor RevisionLibrary: LayoutLibrary {
    private let entry = LibraryEntry(id: UUID(), title: "Layout", origin: .local, modifiedAt: Date())
    private var revisions: [(summary: RevisionSummary, layout: KeyboardLayout)] = []
    private var working: KeyboardLayout

    init(_ layouts: [KeyboardLayout]) {
        working = layouts.last ?? KeyboardLayout(title: "", layers: [])
        revisions = layouts.enumerated().map { n, layout in (Self.summary(n + 1, layout, source: .save, message: nil), layout) }
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
}
