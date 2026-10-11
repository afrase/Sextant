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
        #expect(!model.canShowPreviousLayer && model.canShowNextLayer && !model.canMoveLayerUp && model.canMoveLayerDown)
        model.showAdjacentLayer(1)
        model.showAdjacentLayer(1)
        #expect(session.selection.layer == 2)
        #expect(model.canShowPreviousLayer && !model.canShowNextLayer && !model.canMoveLayerDown)
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

    @Test func buildAndFollowNeedTheirWiring() async throws {
        let unwired = try await openUserLayout()
        #expect(!unwired.canBuild && !unwired.canStop && !unwired.canFollow)
        var commands: [BuildCommand] = []
        let model = try await openUserLayout { command, _ in commands.append(command) }
        #expect(model.canBuild && !model.canStop)
        model.build(.buildAndFlash)
        #expect(commands == [.buildAndFlash])
        model.activity = ActivityState(device: .connected(serial: nil, matchesLayout: true), status: .waitingForFlashMode)
        #expect(!model.canBuild && model.canStop && model.canFollow, "busy: Stop instead of Build; a keyboard allows Follow")
    }

    /// Spec §6.1: deleting a layer other keys switch to asks first; an unreferenced layer goes at once.
    @Test func deletingAReferencedLayerAsksFirst() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        session.select(layer: 2)
        model.requestDeleteLayer()
        #expect(model.layerPendingDeletion == 2)
        #expect(session.layout.layers.count == 3, "nothing is deleted before the answer")
        #expect(model.deletionMessage(for: 2) == "1 key switches to Brd+Sys: key 51 on Main. They will do nothing.")
        model.layerPendingDeletion = nil
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
