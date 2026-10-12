import Foundation
import SextantApplication
import SextantDomain
import SextantStorage
import SextantUI
import SwiftUI

extension Scenes {
    /// The key inspector (spec §5.1–§5.3): a plain key, a dual-function key's hold, a layer hold, an inherited key,
    /// a layer key, a key with its own LED colour, a tap dance slot that can't run and a custom tapping term.
    static func inspector(_ f: Fixtures) async -> [SnapshotScene] {
        var scenes: [SnapshotScene] = []
        func scene(_ name: String, _ model: LayoutWindowModel, id: UUID, slot: KeySlot = .tap) {
            model.session?.select(key: model.session?.selection.keyIndex, slot: slot)
            scenes += SnapshotScene.pair("inspector-\(name)", size: full) { LayoutWindow(model: model, layoutID: .constant(id)) }
        }
        scene("plain", await model(f, key: 13), id: f.entry.id)
        scene("dual", await model(f, key: 19), id: f.entry.id, slot: .hold)
        scene("layer-hold", await model(f, key: 24), id: f.entry.id, slot: .hold)
        scene("inherited", await model(f, layer: 1, key: 24), id: f.entry.id)

        // A layer key and an LED colour come from the every-kind layout, in a library of its own.
        // shortcut: this folder outlives the run (the OS clears temporary files); a Fixtures cleanup hook would remove it.
        guard let base = await model(f).session?.layout else { return scenes }
        let root = FileManager.default.temporaryDirectory.appending(path: "sextant-snapshots-inspector-\(UUID().uuidString)")
        guard let entry = try? await Library(store: PackageLibrary(root: root)).add(imported: kindsLayout(base)) else { return scenes }
        for (name, key) in [("layer-key", 7), ("led", 12)] {
            let model = LayoutWindowModel(library: Library(store: PackageLibrary(root: root)))
            await model.open(entry.id)
            model.session?.select(key: key)
            scene(name, model, id: entry.id)
        }

        // Z double-tapped toggles Brd+Sys, which a dance can't run; ⏎'s hold has its own term (ADR 0041). Each is in a
        // library of its own, so the sidebar lists one layout.
        var danced = base, timed = base
        danced.updateKey(layer: 0, index: 19) { $0.doubleTap = .toggle(2) }
        timed.setTappingTerm(250, layer: 0, index: 24)
        timed.settings["perKeyTappingTerm"] = .bool(true)
        for (layout, name, key, slot) in [(danced, "dance-flagged", 19, KeySlot.doubleTap), (timed, "term-custom", 24, .tap)] {
            let store = PackageLibrary(root: root.appending(path: name))
            guard let entry = try? await Library(store: store).add(imported: layout) else { continue }
            let model = LayoutWindowModel(library: Library(store: store))
            await model.open(entry.id)
            model.session?.select(key: key)
            scene(name, model, id: entry.id, slot: slot)
        }
        return scenes
    }
}
