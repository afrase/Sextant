import Foundation
import SextantApplication
import SextantDomain
import SextantStorage
import SextantUI
import SwiftUI

extension Scenes {
    /// The key inspector (spec §5.1–§5.3): a plain key, a dual-function key's hold, a layer hold, an inherited key,
    /// a layer key and a key with its own LED colour.
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
        return scenes
    }
}
