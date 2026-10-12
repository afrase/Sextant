import Foundation
import SextantApplication
import SextantDomain
import SextantUI
import SwiftUI

/// History and Save Revision (spec §8.7) over the edited-revision fixture: revision 2 on Brd+Sys against its parent.
extension Scenes {
    static func history(_ f: Fixtures) async -> [SnapshotScene] {
        guard let model = await historyModel(f) else { return [] }
        var scenes: [SnapshotScene] = []
        let make = { LayoutWindow(model: model, layoutID: .constant(model.session?.id)) }
        scenes += SnapshotScene.pair("window-history", size: full) { make() }
        scenes.append(SnapshotScene("window-history-min-light", size: CGSize(width: 1120, height: 640)) { make() })
        // Accessibility variants are board scenes, as for the kinds board (Scenes.boards).
        let size = CGSize(width: 1100, height: 560)
        scenes += SnapshotScene.pair("board-history-contrast", size: size, chrome: .content) {
            ChangesBoard(model: model).background(Tokens.benchBase.color).environment(\._colorSchemeContrast, .increased)
        }
        scenes.append(
            SnapshotScene("board-history-dwc-light", size: size, chrome: .content) {
                ChangesBoard(model: model).background(Tokens.benchBase.color).environment(\._accessibilityDifferentiateWithoutColor, true)
            })

        // Save Revision over the window, with the message it suggests for the working copy's edit.
        if let saving = await historyModel(f) {
            saving.destination = .layer(0)
            await saving.beginSaveRevision()
            scenes += SnapshotScene.pair("save-revision", size: full, overlays: [.sheet(width: 440) { SaveRevisionSheet(model: saving) }]) {
                LayoutWindow(model: saving, layoutID: .constant(saving.session?.id))
            }
        }
        return scenes
    }

    /// The fixture on its History page, showing revision 2 on Brd+Sys. Snapshots run no tasks, so the page's load runs here.
    private static func historyModel(_ f: Fixtures) async -> LayoutWindowModel? {
        guard let model = await f.editedRevisionModel(), let session = model.session else { return nil }
        model.buildFlash = await idleBuildFlash(model)
        model.activity = ActivityState(device: connected, status: .notOnKeyboard(edits: 7))
        session.select(layer: 2)
        if let revision = session.revisions.dropFirst().first { await model.showRevision(revision.id) }
        return model
    }
}

/// A Voyager plugged in with live access off: its serial is known from enumeration, and nothing is read or sent.
struct PluggedInKeyboard: DeviceWatcher, KeyboardLink {
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
