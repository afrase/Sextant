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
        #expect(model.layers.pendingDeletion == 2)
        #expect(session.layout.layers.count == 3, "nothing is deleted before the answer")
        #expect(model.deletionMessage(for: 2) == "1 key switches to Brd+Sys: key 51 on Main. It will do nothing.")
        model.layers.pendingDeletion = nil
        session.setKey(Key(tap: .toggle(2), hold: .momentary(2)), layer: 0, index: 5)
        #expect(model.deletionMessage(for: 2).hasPrefix("2 keys switch to Brd+Sys: key 5 on Main, key 51 on Main."), "one entry per key")
        session.addLayer()
        model.requestDeleteLayer()
        #expect(model.layers.pendingDeletion == nil && session.layout.layers.count == 3, "a layer nothing reaches goes at once")
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

    /// Edits restored from a recovery copy say so until the notice is dismissed (ADR 0032), even over a live error.
    @Test func laneSaysWhenEditsWereRecovered() async throws {
        let store = MemoryLibrary()
        let library = Library(store: store)
        let entry = try await library.importOryxJSON(try #require(userLayoutData))
        var edited = try await store.load(entry.id).layout
        edited.title = "Edited before the crash"
        edited.updateKey(layer: 0, index: 13) { $0 = Key("KC_FROM_THE_FUTURE") }
        await store.saveRecovery(edited, for: entry.id)
        let model = LayoutWindowModel(library: library)
        model.destination = .firmwareSettings
        await model.open(nil)
        #expect(model.session?.layout.title == "Edited before the crash" && model.laneStatus == .recovered)
        #expect(model.page == nil, "a layout opens on its board")
        model.session?.recoveredUnsavedChanges = false  // OK
        #expect(model.laneStatus?.isIssue == true, "the unknown keycode's error comes back")
    }

    @Test func kindKeyListsKindsOnTheShownLayer() async throws {
        let model = try await openUserLayout()
        #expect(model.kindsOnLayer == [.regular, .modifier, .dualFunction])
        model.session?.select(layer: 2)
        #expect(model.kindsOnLayer == [.regular, .lighting, .label, .transparent])
    }

    /// Spec §2.2: the destination is a layer's board or a page, and the layer is the session's (ADR 0037).
    @Test func theDestinationIsALayerOrAPage() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        session.select(key: 19)
        #expect(model.destination == .layer(0) && model.page == nil)
        for page in [Destination.firmwareSettings, .combos, .macros, .history, .appLayers] {
            model.destination = page
            #expect(model.destination == page && model.page == page && !model.hasSelectedKey, "\(page) hides the key")
        }
        model.destination = .layer(2)
        #expect(model.page == nil && session.selection.layer == 2 && model.hasSelectedKey, "choosing a layer shows its board")
        session.select(layer: 1)
        #expect(model.destination == .layer(1), "Follow and undo move the layer")
        model.destination = .firmwareSettings
        model.showAdjacentLayer(1)
        #expect(model.destination == .layer(2), "a layer command shows the board")
        model.destination = .history
        model.showAdjacentLayer(-1)
        #expect(model.destination == .history && session.selection.layer == 1, "Combos and History show the board already")
    }

    /// Spec §9.3: esc on the board ends a pick (step 4) before it deselects the key (step 5); a pick click never selects.
    @Test func escCancelsAPickBeforeDeselecting() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        session.select(key: 19)
        var picked: [Int] = []
        var cancels = 0
        let members: @MainActor (Int) -> Bool = { index in
            picked.append(index)
            return picked.count == 2
        }
        model.boardPick = BoardPick(prompt: "Click 2 keys", onPick: members) { cancels += 1 }
        model.click(key: 3)
        #expect(picked == [3] && model.boardPick != nil && session.selection.keyIndex == 19)
        #expect(model.typeOnBoard("a") == false && model.palette == nil, "typing opens no picker under a pick")
        model.escapeBoard()
        #expect(model.boardPick == nil && cancels == 1 && session.selection.keyIndex == 19)
        model.escapeBoard()
        #expect(session.selection.keyIndex == nil)
        model.click(key: 7)
        #expect(session.selection.keyIndex == 7, "without a pick a click selects")

        model.boardPick = BoardPick(prompt: "Click a key", onPick: members) { cancels += 1 }
        #expect(model.typeOnBoard("") && picked == [3, 7], "⏎ picks the selected key, for the keyboard alone")
        #expect(model.boardPick == nil && cancels == 1 && model.palette == nil, "a finished pick ends without cancelling")

        let other = try await model.library.importOryxJSON(try #require(userLayoutData))
        model.boardPick = BoardPick(prompt: "Click a key", onPick: { _ in true }) { cancels += 1 }
        model.openKeycodePicker(AssignTarget(title: "Combo 1 › Output") { _ in })
        await model.open(other.id)
        #expect(model.boardPick == nil && cancels == 2 && model.palette == nil, "another layout cancels what was made for this one")
    }

    /// A rename, a confirmation or a sheet left up names a layer of the last layout; the next one's must not take it. The
    /// last layout's import isn't the next one's either.
    @Test func anotherLayoutDropsWhatNamedTheLastOnesLayers() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        model.layers.renamingID = session.layout.layers.first?.id
        model.layers.pendingClear = 2
        model.layers.pendingDeletion = 2
        model.lighting.keyColoursPendingClear = 1
        model.lighting.layerPendingColour = 1
        model.lighting.pickBrush(HexColor(red: 0, green: 0, blue: 1))
        model.importedLayout = session.layout
        #expect(model.isEditingText)

        let other = try await model.library.importOryxJSON(try #require(userLayoutData))
        await model.open(other.id)
        #expect(model.layers.renamingID == nil && model.layers.pendingClear == nil && model.layers.pendingDeletion == nil)
        #expect(model.lighting.keyColoursPendingClear == nil && model.lighting.layerPendingColour == nil)
        #expect(model.lighting.brushColor == HexColor(red: 0, green: 0, blue: 1), "the brush is the user's, not the layout's")
        #expect(model.importedLayout == nil && !model.isEditingText)
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
