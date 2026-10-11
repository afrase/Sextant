import Foundation
import SextantApplication
import SextantDomain
import SwiftUI
import Testing

@testable import SextantUI

/// Layer management (spec §6.1) and the Lighting lens (§6.2) on the user's layout: Main, Sym+Num (held by key 24
/// on Main), Brd+Sys (held by key 51 on Main).
@MainActor
struct LayersAndLightingTests {
    /// An undo manager per test; the session holds it weakly, as it does the window's.
    private func undoable(_ session: EditSession) -> UndoManager {
        let undo = UndoManager()
        undo.groupsByEvent = false
        session.undoManager = undo
        return undo
    }

    /// One user action as one undo group, the way an event loop groups it.
    private func step(_ undo: UndoManager, _ action: () -> Void) {
        undo.beginUndoGrouping()
        action()
        undo.endUndoGrouping()
    }

    @Test func newLayerStartsRenamingWhereTheSidebarShows() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        model.addLayer()
        #expect(session.layout.layers.count == 4 && session.selection.layer == 3)
        #expect(model.renamingLayerID == session.layout.layers[3].id)
        model.renamingLayerID = nil
        model.columnVisibility = .detailOnly
        model.addLayer()
        #expect(session.layout.layers.count == 5)
        #expect(model.renamingLayerID == nil, "no rename in a sidebar nobody can see")
    }

    @Test func renamingInPlaceCommitsOnceAndKeepsANameOnBlank() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        let id = session.layout.layers[1].id
        model.startRenaming(layer: 1)
        model.finishRenaming(id, to: "   ")
        #expect(session.layout.layers[1].title == "Sym+Num" && model.renamingLayerID == nil, "a blank name keeps the old one")
        model.startRenaming(layer: 1)
        model.finishRenaming(id, to: " Nav ")
        model.finishRenaming(id, to: "Other")
        #expect(session.layout.layers[1].title == "Nav", "Return then leaving the field renames once")
    }

    /// Spec §3.6: a drag is one "Move Layer" step and layer keys follow the layer.
    @Test func draggingALayerIsOneStepAndKeysFollow() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        let undo = undoable(session)
        step(undo) { model.moveLayer(fromOffsets: [1], toOffset: 3) }
        #expect(session.layout.layers.map(\.title) == ["Main", "Brd+Sys", "Sym+Num"])
        #expect(session.layout.layers[0].keys[24].hold?.layer == 2, "⏎ still holds Sym+Num")
        #expect(session.layout.layers[0].keys[51].hold?.layer == 1, "Space still holds Brd+Sys")
        #expect(undo.undoActionName == "Move Layer")
        undo.undo()
        #expect(session.layout.layers.map(\.title) == ["Main", "Sym+Num", "Brd+Sys"])
        step(undo) { model.moveLayer(fromOffsets: [2], toOffset: 0) }
        #expect(session.layout.layers.map(\.title) == ["Brd+Sys", "Main", "Sym+Num"], "upwards, the offset is the index")
        step(undo) { model.moveLayer(fromOffsets: [0], toOffset: 1) }
        #expect(session.layout.layers.map(\.title) == ["Brd+Sys", "Main", "Sym+Num"], "dropping a layer on itself does nothing")
    }

    @Test func clearKeyColoursClearsOnlyThatLayerInOneStep() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        let undo = undoable(session)
        let orange = try #require(HexColor(hex: "#FF9500"))
        step(undo) { session.paint(orange, keys: [3, 4, 5], layer: 2) }
        step(undo) { session.paint(orange, keys: [7], layer: 1) }
        #expect(model.keysWithOwnColour(on: 2) == [3, 4, 5])
        step(undo) { model.clearKeyColours(on: 2) }
        #expect(model.keysWithOwnColour(on: 2).isEmpty && model.keysWithOwnColour(on: 1) == [7])
        undo.undo()
        #expect(model.keysWithOwnColour(on: 2) == [3, 4, 5], "one undo brings every colour back")
    }

    @Test func theBrushPaintsOnlyInTheLightingLens() async throws {
        let model = try await openUserLayout()
        #expect(model.brush == nil)
        model.lens = .lighting
        #expect(model.brush == Brush(color: model.brushColor))
        model.isErasing = true
        #expect(model.brush == Brush(color: nil), "the eraser removes keys' own colours")
        let teal = try #require(HexColor(hex: "#00C7BE"))
        model.pickBrush(teal)
        #expect(model.brush == Brush(color: teal), "picking a colour puts the eraser down")
        #expect(model.swatches == KeyboardLayout.defaultSwatch, "the user's layout has no swatches of its own")
    }

    @Test func aKeyLightsWithItsOwnColourThenItsLayers() throws {
        let own = try #require(HexColor(hex: "#FF9500"))
        let layer = try #require(HexColor(hex: "#42FF00"))
        #expect(KeyLight(own: own, layer: layer) == .own(own))
        #expect(KeyLight(own: nil, layer: layer).tint?.strength == 0.35, "inherited light is quieter so painted keys pop")
        #expect(KeyLight(own: nil, layer: nil) == .off && KeyLight.off.tint == nil)
    }

    @Test func pickedColoursSnapToStoredHex() throws {
        let picked = try #require(HexColor(Color(.sRGB, red: 0.5004, green: 0.25, blue: 1)))
        #expect(picked.hex == "#8040FF")
        #expect(HexColor(hex: picked.hex) == picked, "what the picker sets is what the file reads back")
    }
}
