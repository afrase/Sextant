import Foundation
import SextantApplication
import SextantDomain
import Testing

@testable import SextantUI

@MainActor
struct LayoutWindowModelTests {
    @Test func opensTheMostRecentLayoutAndKeepsItsSession() async throws {
        let library = Library(store: MemoryLibrary())
        #expect(await LayoutWindowModel(library: library).open(nil) == nil, "an empty library opens nothing")
        let entry = try await library.importOryxJSON(try #require(userLayoutData))
        let model = LayoutWindowModel(library: library)
        #expect(await model.open(nil) == entry.id)
        let session = try #require(model.session)
        #expect(await model.open(entry.id) == entry.id)
        #expect(model.session === session, "opening the same layout keeps the session")
        #expect(await model.open(UUID()) == entry.id, "a stale restored id falls back to the most recent layout")
        #expect(model.loadError == nil)
    }

    /// One window per layout (spec §2.1): two documents for one layout would overwrite each other's autosaves.
    @Test func aSecondWindowOpensAnotherLayout() async throws {
        let library = Library(store: MemoryLibrary())
        let data = try #require(userLayoutData)
        let first = try await library.importOryxJSON(data)
        let window1 = LayoutWindowModel(library: library)
        #expect(await window1.open(nil) == first.id)
        let window2 = LayoutWindowModel(library: library)
        #expect(await window2.open(nil) == nil, "the only layout is open in the first window")
        #expect(await window2.open(first.id) == nil, "a restored window can't take it either")
        let second = try await library.importOryxJSON(data)
        #expect(await window2.open(nil) == second.id)
        #expect(await window2.open(first.id) == second.id, "it keeps its own layout")
        await window1.close()
        #expect(await window2.open(first.id) == first.id, "a closed window frees its layout")
    }

    /// Spec §3.4: the subtitle is the layer, plus " · Edited" until the layout matches the last revision again.
    @Test func subtitleSaysEditedUntilUndoneOrSaved() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        let undo = UndoManager()  // the session holds it weakly, as it does the window's
        undo.groupsByEvent = false
        session.undoManager = undo
        session.select(layer: 1)
        #expect(model.subtitle == "Sym+Num")
        undo.beginUndoGrouping()
        session.makeTransparent(index: 3)
        undo.endUndoGrouping()
        #expect(model.subtitle == "Sym+Num · Edited")
        undo.undo()
        #expect(model.subtitle == "Sym+Num", "undoing back to the revision clears Edited")
        undo.redo()
        try await session.saveRevision(source: .save, message: nil)
        #expect(!session.isEditedSinceRevision, "a new revision is the new baseline")
    }

    /// Spec §9.1: layer commands are enabled only where they can act.
    @Test func layerCommandEnablement() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        #expect(!model.canShowPreviousLayer && model.canShowNextLayer)
        model.showAdjacentLayer(1)
        model.showAdjacentLayer(1)
        #expect(session.selection.layer == 2)
        #expect(model.canShowPreviousLayer && !model.canShowNextLayer)
        model.showAdjacentLayer(1)
        #expect(session.selection.layer == 2, "showing past the last layer does nothing")
        #expect(model.canDeleteLayer)
    }

    @Test func keyCommandEnablement() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        #expect(!model.hasSelectedKey && !model.canOverrideKey)
        session.select(layer: 1)
        session.select(key: 19)
        #expect(model.hasSelectedKey && model.canOverrideKey, "Sym+Num key 19 inherits Z from Main")
        session.select(key: 0)
        #expect(!model.canOverrideKey, "Sym+Num key 0 is its own")
    }

    /// Spec §6.1: deleting a layer other keys switch to asks first; an unreferenced layer goes at once.
    @Test func deletingAReferencedLayerAsksFirst() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        session.select(layer: 2)
        model.requestDeleteLayer()
        #expect(model.layerPendingDeletion == 2)
        #expect(session.layout.layers.count == 3, "nothing is deleted before the answer")
        #expect(model.deletionMessage(for: 2) == "1 key switches to Brd+Sys: key 51 on Main. It will do nothing.")
        model.layerPendingDeletion = nil
        session.setKey(Key(tap: .toggle(2), hold: .momentary(2)), layer: 0, index: 5)
        #expect(model.deletionMessage(for: 2).hasPrefix("2 keys switch to Brd+Sys: key 5 on Main, key 51 on Main."), "one entry per key")
        session.addLayer()
        model.requestDeleteLayer()
        #expect(model.layerPendingDeletion == nil && session.layout.layers.count == 3, "a layer nothing reaches goes at once")
    }

    @Test func laneShowsLiveWhileFollowing() async throws {
        let model = try await openUserLayout()
        #expect(model.laneStatus == nil)
        model.session?.select(layer: 2)
        model.isFollowing = true
        #expect(model.laneStatus == .live(text: "LIVE · Brd+Sys held by Space (key 51)"))
        #expect(model.readout == "LIVE · following the keyboard")
        model.activity = ActivityState()
        #expect(!model.isFollowing && model.laneStatus == nil, "unplugging the keyboard ends Follow")
    }

    @Test func kindKeyListsKindsOnTheShownLayer() async throws {
        let model = try await openUserLayout()
        #expect(model.kindsOnLayer == [.regular, .modifier, .dualFunction])
        model.session?.select(layer: 2)
        #expect(model.kindsOnLayer == [.regular, .lighting, .label, .transparent])
    }

    /// Spec §3.2: the window minimum is 640 plus the visible columns' minimums.
    @Test func honestMinimumWidths() async throws {
        let model = try await openUserLayout()
        #expect(model.minimumWidth == 1120)
        model.showsInspector = false
        #expect(model.minimumWidth == 840)
        model.columnVisibility = .detailOnly
        #expect(model.minimumWidth == 640)
        model.showsInspector = true
        #expect(model.minimumWidth == 920)
    }
}
