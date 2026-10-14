import Foundation
import SextantApplication
import SextantDomain
import SextantStorage
import SextantUI
import SwiftUI

/// Import from Oryx, the Firmware Settings page, the Settings panes and the Welcome window (spec §8.1, §8.8, §8.9, §12.1).
extension Scenes {
    static func `import`(_ f: Fixtures) async -> [SnapshotScene] {
        var scenes: [SnapshotScene] = []
        let link = "https://configure.zsa.io/voyager/layouts/KlgM7/40xJ7M/0"
        let layout = (try? Data(contentsOf: oryxExample("my-layout-KlgM7-40xJ7M.json"))).flatMap { try? KeyboardLayout(oryxJSON: $0) }

        // The sheet over the window: empty, a valid link (not fetched yet), the preview, and the offline error.
        let behind = await model(f, key: 19)
        func sheet(_ name: String, oryx: some OryxReader, input: String = "", fetch: Bool = false) async {
            // Snapshots run no tasks, so the sheet doesn't fetch a filled-in link itself; `fetch` does it here.
            let flow = ImportFromOryx(oryx: oryx, library: behind.library)
            flow.input = input
            if fetch { await flow.fetch() }
            scenes += SnapshotScene.pair(name, size: full, overlays: [.sheet(width: 560) { ImportSheet(flow: flow, model: behind) }]) {
                LayoutWindow(model: behind, layoutID: .constant(f.entry.id))
            }
        }
        await sheet("import-empty", oryx: SnapshotOryx(layout: layout))
        await sheet("import-link", oryx: SnapshotOryx(layout: layout), input: link)
        await sheet("import-preview", oryx: SnapshotOryx(layout: layout), input: link, fetch: true)
        await sheet("import-error", oryx: SnapshotOryx(layout: nil), input: link, fetch: true)

        // Firmware Settings with changed settings, on the layout with its Navigator trackpad, in a library of its own
        // so the edits' autosave can't reach other scenes. Also at the honest minimum with both columns.
        if let firmware = await ownLibraryModel(importing: "my-layout-KlgM7-full.json"), let session = firmware.session {
            session.setSetting("tappingTerm", to: .number(180))
            session.setSetting("flowTap", to: .number(100))
            session.setSetting("automouseTime", to: .number(800))
            firmware.destination = .firmwareSettings
            let make = { LayoutWindow(model: firmware, layoutID: .constant(session.id)) }
            scenes += SnapshotScene.pair("firmware-settings", size: full) { make() }
            scenes += SnapshotScene.pair("firmware-settings-min", size: CGSize(width: 1120, height: 640)) { make() }
        }

        // The Navigator section with the trackpad swapped for a trackball on the left, and with none; the board with the
        // trackball's disc on the left (ADR 0035). Offscreen renders don't scroll, so the window is tall enough for the
        // whole form, Navigator last.
        for (name, kind, height) in [("navigator", NavigatorConfig.Kind.trackball, 6400.0), ("navigator-none", nil, 5300.0)] {
            if let model = await ownLibraryModel(importing: "my-layout-KlgM7-full.json"), let session = model.session {
                session.moveNavigator(to: .left)
                session.setNavigator(kind)
                model.destination = .firmwareSettings
                scenes += SnapshotScene.pair("firmware-settings-\(name)", size: CGSize(width: full.width, height: height)) {
                    LayoutWindow(model: model, layoutID: .constant(session.id))
                }
            }
        }
        if let model = await ownLibraryModel(importing: "my-layout-KlgM7-full.json"), let session = model.session {
            session.setNavigator(.trackball)
            session.moveNavigator(to: .left)
            scenes += SnapshotScene.pair("board-navigator-left", size: full) { LayoutWindow(model: model, layoutID: .constant(session.id)) }
        }

        // Settings panes (spec §8.9).
        let setup = ToolchainStatus.needsSetup("Building firmware needs a one-time download of the build tools (about 199 MB).")
        let status: BuildToolsStatus = { setup }
        scenes += SnapshotScene.pair("settings-general", size: CGSize(width: 520, height: 230), chrome: .window(title: "General")) {
            GeneralSettings()
        }
        scenes += SnapshotScene.pair("settings-build", size: CGSize(width: 520, height: 370), chrome: .window(title: "Build")) {
            BuildSettings(
                status: status, source: ("93b2b9ec3368f86c5eb5a2e3f934049f8daef885", "13890cd7856175de20798689d15ba6a46bf0c5c7"),
                known: setup)
        }
        scenes += SnapshotScene.pair("settings-privacy", size: CGSize(width: 520, height: 400), chrome: .window(title: "Privacy")) {
            PrivacySettings()
        }

        // Welcome: an empty library, at the default size and at 640×640 with both columns hidden.
        if let empty = await ownLibraryModel(importing: nil) {
            let make = { LayoutWindow(model: empty, layoutID: .constant(nil)) }
            scenes += SnapshotScene.pair("welcome", size: full) { make() }
        }
        if let bare = await ownLibraryModel(importing: nil) {
            bare.columnVisibility = .detailOnly
            bare.showsInspector = false
            scenes += SnapshotScene.pair("welcome-min", size: CGSize(width: 640, height: 640)) {
                LayoutWindow(model: bare, layoutID: .constant(nil))
            }
        }
        return scenes
    }

    private static func oryxExample(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "docs/research/oryx-examples/\(name)")
    }

    /// A window model over a throwaway library of its own, with importing wired so the Welcome cards draw enabled.
    private static func ownLibraryModel(importing file: String?) async -> LayoutWindowModel? {
        let root = FileManager.default.temporaryDirectory.appending(path: "sextant-snapshots-\(UUID().uuidString)")
        let library = Library(store: PackageLibrary(root: root))
        if let file {
            guard let data = try? Data(contentsOf: oryxExample(file)), (try? await library.importOryxJSON(data)) != nil else { return nil }
        }
        let model = LayoutWindowModel(library: library, makeImport: { ImportFromOryx(oryx: SnapshotOryx(layout: nil), library: library) })
        await model.open(nil)
        return model
    }
}

/// Oryx for snapshots: answers with a fixed layout, or is offline. Never touches the network.
private struct SnapshotOryx: OryxReader {
    var layout: KeyboardLayout?

    func layout(_ reference: OryxReference) async throws(OryxError) -> KeyboardLayout {
        guard let layout else { throw .offline }
        return layout
    }

    func firmware(revisionID: String, expectedMD5: String) async throws(OryxError) -> Data { Data() }
}
