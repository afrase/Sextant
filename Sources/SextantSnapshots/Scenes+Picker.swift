import SextantUI
import SwiftUI

extension Scenes {
    /// The keycode picker over the board, the command palette and Record Key (spec §5.6–§5.8).
    static func picker(_ f: Fixtures) async -> [SnapshotScene] {
        var scenes: [SnapshotScene] = []
        func window(_ name: String, _ model: LayoutWindowModel, size: CGSize = full, light: Bool = false) {
            let make = { LayoutWindow(model: model, layoutID: .constant(f.entry.id)) }
            scenes += light ? [SnapshotScene("\(name)-light", size: size) { make() }] : SnapshotScene.pair(name, size: size) { make() }
        }

        // Z (key 19, left hand): the picker floats over the right half, previewing the top result on the cap.
        let picking = await model(f, key: 19)
        picking.openKeycodePicker(prefilled: "bra")
        window("picker-query", picking)

        // Browsing Suggested for a hold at the honest minimum: modifiers and layers, the rail as icons.
        let browsing = await model(f, layer: 1, key: 43)
        browsing.session?.select(key: 43, slot: .hold)
        browsing.openKeycodePicker()
        window("picker-browse-min", browsing, size: CGSize(width: 1120, height: 640), light: true)

        // An inner thumb as the target at the minimum: the picker narrows to stay clear of it.
        let thumb = await model(f, key: 50)
        thumb.openKeycodePicker()
        window("picker-thumb-min", thumb, size: CGSize(width: 1120, height: 640), light: true)

        // ⌘K with a query: commands, keys, layers, keycodes for the selected key and firmware settings.
        let palette = await model(f, layer: 1, key: 24)
        palette.openPalette(query: "layer")
        window("palette-query", palette)

        // A pasted Oryx link offers Import from Oryx… first.
        let link = await model(f)
        link.openPalette(query: "https://configure.zsa.io/voyager/layouts/KlgM7/40xJ7M/0")
        window("palette-oryx", link, light: true)

        // Record Key: the lens lane's Recording capsule and the REC cap.
        let recording = await model(f, key: 19)
        recording.startRecording()
        window("record", recording)
        return scenes
    }
}
