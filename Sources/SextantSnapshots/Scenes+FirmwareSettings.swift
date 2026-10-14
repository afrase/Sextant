import Foundation
import SextantApplication
import SextantDomain
import SextantStorage
import SextantUI
import SwiftUI

// The Firmware Settings page with every section (spec §8.8, ADR 0040): search, Modified only, the animation list and a
// trackball Navigator. Each scene edits the user's layout in a library of its own, so the autosave can't reach others.

extension Scenes {
    /// Offscreen renders don't scroll: the whole form needs a window this tall (a trackball's options take more).
    private static let wholeForm = CGSize(width: 1440, height: 5700)
    private static let wholeTrackballForm = CGSize(width: 1440, height: 6400)

    static func firmwareSettings(_ f: Fixtures) async -> [SnapshotScene] {
        var scenes: [SnapshotScene] = []
        let minimum = CGSize(width: 1120, height: 640)
        func add(_ name: String, sizes: [(String, CGSize)] = [("", full)], edit: (LayoutWindowModel, EditSession) -> Void) async {
            guard let model = await settingsModel(), let session = model.session else { return }
            edit(model, session)
            model.destination = .firmwareSettings
            for (suffix, size) in sizes {
                scenes += SnapshotScene.pair("firmware-settings-\(name)\(suffix)", size: size) {
                    LayoutWindow(model: model, layoutID: .constant(session.id))
                }
            }
        }

        // Every section, with coupled changes: Chordal hold turned Exclude thumbs on, Auto Shift its key groups.
        await add("all", sizes: [("", wholeForm)]) { _, session in changeSome(session) }
        // ⌘F: "hold" matches titles, descriptions and synonyms; also at the minimum window.
        await add("search", sizes: [("", full), ("-min", minimum)]) { model, session in
            changeSome(session)
            model.firmwareSettings.query = "hold"
        }
        // With two values only an Oryx import can carry, which the inspector lists as kept (tall enough to show them).
        await add("modified", sizes: [("", CGSize(width: full.width, height: 1100))]) { model, session in
            changeSome(session)
            session.setSetting("liveTraining", to: .bool(false))
            session.setSetting("german", to: .bool(true))
            model.firmwareSettings.modifiedOnly = true
        }
        // The animation list open, two left out.
        await add("animations") { model, session in
            session.setSetting("disabledAnimations", to: .strings(["breathing", "digitalRain"]))
            model.firmwareSettings.query = "animations"
            model.firmwareSettings.showsAnimations = true
        }
        // A trackball on the left with one-shot auto-mouse on: the idle timeout is a trackpad option, so an imported one
        // isn't there and is listed as kept.
        await add("trackball", sizes: [("", wholeTrackballForm)]) { _, session in
            session.setNavigator(.trackball)
            session.moveNavigator(to: .left)
            session.setSetting("oneShotAutoMouse", to: .bool(true))
            session.setSetting("oneShotAutoMouseTimeout", to: .number(5))
            session.setSetting("aimLayers", to: .integers([1]))
            session.setSetting("sensitivity", to: .number(60))
        }
        // Auto Shift off with a delay an import kept: the Auto Shift options wait for it, and the delay can still be reset.
        await add("waiting", sizes: [("", full), ("-min", minimum)]) { model, session in
            session.setSetting("autoshiftTimeout", to: .number(150))
            model.firmwareSettings.query = "shift"
        }
        // The empty states keep the header at the top: no match, and Modified only with nothing changed.
        await add("no-match", sizes: [("-min", minimum)]) { model, _ in model.firmwareSettings.query = "zzzz" }
        await add("none-changed", sizes: [("-min", minimum)]) { model, _ in model.firmwareSettings.modifiedOnly = true }
        // The module choice counts as a match.
        await add("navigator-query", sizes: [("-min", minimum)]) { model, _ in model.firmwareSettings.query = "trackball" }
        // The picker says where English (UK)'s £ went while its toggle is off.
        if let model = await settingsModel(), let session = model.session {
            session.select(key: 19)
            model.openKeycodePicker(prefilled: "pound")
            scenes += SnapshotScene.pair("picker-locale-off", size: full) { LayoutWindow(model: model, layoutID: .constant(session.id)) }
        }
        return scenes
    }

    /// Changes that show a changed row, an inline coupling and a Navigator option.
    private static func changeSome(_ session: EditSession) {
        session.setSetting("tappingTerm", to: .number(180))
        session.setSetting("chordalHold", to: .bool(true))
        session.setSetting("autoshift", to: .bool(true))
        session.setSetting("uk", to: .bool(true))
        session.setSetting("mouseMaxSpeed", to: .number(12))
        session.setSetting("automouseTime", to: .number(800))
    }

    /// The user's layout, with its Navigator trackpad, in a throwaway library of its own.
    private static func settingsModel() async -> LayoutWindowModel? {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "docs/research/oryx-examples/my-layout-KlgM7-full.json")
        let library = Library(
            store: PackageLibrary(root: FileManager.default.temporaryDirectory.appending(path: "sextant-snapshots-\(UUID().uuidString)")))
        guard let data = try? Data(contentsOf: file), (try? await library.importOryxJSON(data)) != nil else { return nil }
        let model = LayoutWindowModel(library: library)
        await model.open(nil)
        return model
    }
}
