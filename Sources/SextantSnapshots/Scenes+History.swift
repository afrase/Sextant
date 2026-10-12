import Foundation
import SextantApplication
import SextantDomain
import SextantStorage
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

        // A long History scrolls its timeline, so the selected revision's details stay in view.
        if let many = await historyModel(f), let session = many.session {
            for n in 1...12 {
                _ = try? await session.recordRevision(RevisionDraft(source: .flash, message: "Flash \(n)", layout: session.layout))
            }
            if let revision = session.revisions.dropFirst().first { await many.showRevision(revision.id) }
            scenes.append(
                SnapshotScene("window-history-many-light", size: full) { LayoutWindow(model: many, layoutID: .constant(many.session?.id)) })
        }
        // No revisions yet (§12.4): only a package made outside Sextant starts without one.
        if let empty = await emptyHistoryModel() {
            scenes.append(
                SnapshotScene("window-history-empty-light", size: full) {
                    LayoutWindow(model: empty, layoutID: .constant(empty.session?.id))
                })
        }

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

    private static func emptyHistoryModel() async -> LayoutWindowModel? {
        let store = PackageLibrary(root: FileManager.default.temporaryDirectory.appending(path: "sextant-snapshots-\(UUID().uuidString)"))
        guard let data = try? Data(contentsOf: Fixtures.layoutFile), let layout = try? KeyboardLayout(oryxJSON: data),
            let entry = try? await store.create(layout, origin: .local, firstRevision: nil)
        else { return nil }
        let library = Library(store: store)
        await library.refresh()
        let model = LayoutWindowModel(library: library)
        await model.open(entry.id)
        model.destination = .history
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
