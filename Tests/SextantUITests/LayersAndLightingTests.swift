import Foundation
import SextantApplication
import SextantDomain
import SwiftUI
import Synchronization
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
        #expect(model.layers.renamingID == session.layout.layers[3].id)
        model.layers.renamingID = nil
        model.columnVisibility = .detailOnly
        model.addLayer()
        #expect(session.layout.layers.count == 5)
        #expect(model.layers.renamingID == nil, "no rename in a sidebar nobody can see")
    }

    @Test func renamingInPlaceCommitsOnceAndKeepsANameOnBlank() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        let id = session.layout.layers[1].id
        model.startRenaming(layer: 1)
        model.finishRenaming(id, to: "   ")
        #expect(session.layout.layers[1].title == "Sym+Num" && model.layers.renamingID == nil, "a blank name keeps the old one")
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
        #expect(model.keysWithOwnColour(on: 2) == [3, 4, 5], "one undo brings every color back")
    }

    @Test func theBrushPaintsOnlyInTheLightingLens() async throws {
        let model = try await openUserLayout()
        #expect(model.brush == nil)
        model.lens = .lighting
        #expect(model.brush == Brush(color: model.lighting.brushColor))
        model.lighting.isErasing = true
        #expect(model.brush == Brush(color: nil), "the eraser removes keys' own colors")
        let teal = try #require(HexColor(hex: "#00C7BE"))
        model.lighting.pickBrush(teal)
        #expect(model.brush == Brush(color: teal), "picking a color puts the eraser down")
        #expect(model.swatches == KeyboardLayout.defaultSwatch, "the user's layout has no swatches of its own")
    }

    @Test func aStrokeChangesOnlyColoursInOneStep() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        let undo = undoable(session)
        let before = session.layout.layers[2].keys
        let orange = try #require(HexColor(hex: "#FF9500"))
        step(undo) { session.paint(orange, keys: Array(14...20), layer: 2) }
        let after = session.layout.layers[2].keys
        for i in before.indices {
            var expected = before[i]
            if (14...20).contains(i) { expected.glowColor = orange }
            #expect(after[i] == expected, "key \(i) keeps its actions")
        }
        #expect(undo.undoActionName == "Paint 7 Keys")
        undo.undo()
        #expect(session.layout.layers[2].keys == before)
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

/// The window's side of the keyboard lighting preview (spec §6.2, ADR 0051), over a stand-in keyboard that pairs at once and
/// answers `05` like the firmware: nothing here writes to a keyboard.
@MainActor
struct KeyboardLightingPreviewTests {
    private let link = PreviewLink()
    let live: LiveSession
    let preview: LightingPreview

    init() {
        live = LiveSession(watcher: PreviewKeyboard(), link: link, secureInputProbe: { false })
        preview = LightingPreview(live: live)
        live.start()
        preview.start()
    }

    /// A window on the user's layout, showing Brd+Sys (#42FF00 on every key) with Live View on, and feeding the preview as
    /// the window does.
    func window(liveView: Bool = true) async throws -> LayoutWindowModel {
        let library = Library(store: MemoryLibrary())
        _ = try await library.importOryxJSON(try #require(userLayoutData))
        let model = LayoutWindowModel(library: library, live: live, lightingPreview: preview)
        await model.open(nil)
        model.session?.select(layer: 2)
        try #require(await eventually { live.connection != .noKeyboard })
        if liveView {
            model.isLive = true
            try #require(await eventually { live.canSend })
        }
        Task { await model.feedKeyboardLighting() }
        return model
    }

    /// The model previewing, once its first frame is out.
    func previewing() async throws -> LayoutWindowModel {
        let model = try await window()
        model.previewsLighting = true
        try #require(await eventually { link.commands.count == 2 })
        return model
    }

    @Test func turningItOnShowsLightingAndSendsTheShownLayerAsItChanges() async throws {
        let model = try await window()
        #expect(model.lens == .keys && model.lightingPreviewRefusal == nil)
        model.destination = .macros
        model.previewsLighting = true
        #expect(model.lens == .lighting && model.destination == .layer(2), "the switch shows what it previews")
        #expect(await eventually { link.commands == [.lighting(true), .setAllLEDs(red: 0x42, green: 0xFF, blue: 0)] })

        let orange = try #require(HexColor(hex: "#FF9500"))
        model.session?.paint(orange, keys: [14], layer: 2)
        #expect(await eventually { link.commands.last == .setLED(index: 14, red: 0xFF, green: 0x95, blue: 0) })
        model.session?.select(layer: 1)
        #expect(await eventually { link.commands.last == .setAllLEDs(red: 0, green: 0xF0, blue: 0xFF) }, "Sym+Num")
        #expect(!link.commands.contains(.lighting(false)))
    }

    @Test(arguments: ["switch off", "Keys lens", "a page", "another layout", "window closed", "Live View off"])
    func everyWayOutGivesTheLightsBack(_ path: String) async throws {
        let model = try await previewing()
        switch path {
        case "switch off": model.previewsLighting = false
        case "Keys lens": model.lens = .keys
        case "a page": model.destination = .history
        case "another layout":
            let other = try await model.library.importOryxJSON(try #require(userLayoutData))
            await model.open(other.id)
        case "window closed": await model.close()
        default:
            model.isLive = false
            #expect(!model.isLive, "off at once, while the keyboard gets its lights back")
        }
        #expect(await eventually { link.commands.last == .lighting(false) })
        #expect(await eventually { !model.previewsLighting })
        #expect(link.commands.filter { $0 == .lighting(false) }.count == 1)
    }

    /// The last click wins: Live View turned on again while the lights go back pairs again once they have.
    @Test func liveViewOffThenOnStaysOn() async throws {
        let model = try await previewing()
        model.isLive = false
        model.isLive = true
        #expect(model.isLive)
        #expect(await eventually { link.sessions == 2 && live.canSend })
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.isLive && live.isLive)
        #expect(link.commands.filter { $0 == .lighting(false) }.count == 1)
    }

    @Test func aSecondWindowSaysWhereThePreviewIs() async throws {
        let first = try await previewing()
        let second = try await window()
        #expect(second.lightingPreviewRefusal == .previewingElsewhere("My MacOS Layout"))
        second.previewsLighting = true
        #expect(!second.previewsLighting && first.previewsLighting)
        second.lens = .lighting
        try await Task.sleep(for: .milliseconds(20))
        #expect(link.commands.count == 2, "the second window sends nothing")
    }

    @Test func withLiveViewOffItAsksForLiveView() async throws {
        let model = try await window(liveView: false)
        #expect(model.lightingPreviewRefusal == .liveOff && model.canGoLive)
        model.previewsLighting = true
        #expect(!model.previewsLighting && model.lens == .keys)
        #expect(link.sessions == 0, "nothing paired, nothing written")
    }

    @Test func withoutAKeyboardThereIsNoPreview() async throws {
        let model = try await openUserLayout()
        #expect(model.lightingPreviewRefusal == .noKeyboard)
        model.previewsLighting = true
        #expect(!model.previewsLighting && model.keyboardLightingFrame == nil)
    }
}

/// A Voyager already plugged in.
private struct PreviewKeyboard: DeviceWatcher {
    func events(for board: BoardDefinition) -> AsyncStream<DeviceEvent> {
        AsyncStream { $0.yield(.attached(.keyboard(KeyboardDevice(id: 1, productID: 0x1977, serial: "KlgM7/40xJ7M")))) }
    }
}

/// Sessions that pair at once on layer 0, record the commands they get, and answer `05` with `08` as the firmware does.
private final class PreviewLink: KeyboardLink {
    private let state = Mutex<(sessions: Int, commands: [KeyboardCommand])>((0, []))

    var sessions: Int { state.withLock { $0.sessions } }
    var commands: [KeyboardCommand] { state.withLock { $0.commands } }

    func session(with device: KeyboardDevice, board: BoardDefinition, commands: AsyncStream<KeyboardCommand>) -> AsyncStream<LiveEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: LiveEvent.self)
        state.withLock { $0.sessions += 1 }
        continuation.yield(.layer(0))
        Task { [self] in
            for await command in commands {
                self.state.withLock { $0.commands.append(command) }
                if case let .lighting(on) = command { continuation.yield(.lighting(on)) }
            }
        }
        return stream
    }
}

/// Polls `condition`, letting other tasks run, for up to about five seconds: a loaded runner can take more than one.
@MainActor
private func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<500 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    return condition()
}
