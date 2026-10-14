import SextantApplication
import SextantDomain
import SextantUI
import SwiftUI

extension Scenes {
    /// Several selected keys (spec §5.4, ADR 0047): a ring on each, the "4 keys" inspector and its picker target, and
    /// Copy Layer To in the sidebar's context menu. All on the user's own layout.
    static func multiSelect(_ f: Fixtures) async -> [SnapshotScene] {
        var scenes: [SnapshotScene] = []
        func window(_ name: String, _ model: LayoutWindowModel, size: CGSize = full, overlays: [SnapshotOverlay] = []) {
            scenes += SnapshotScene.pair(name, size: size, overlays: overlays) {
                LayoutWindow(model: model, layoutID: .constant(f.entry.id))
            }
        }

        // A S D F on Main: each tap differs, so the slot editor says "Mixed".
        let mixed = await model(f, key: 13)
        mixed.session?.select(keys: [13, 14, 15, 16], anchor: 13)
        window("multiselect", mixed)
        let minimum = await model(f, key: 13)
        minimum.session?.select(keys: [13, 14, 15, 16], anchor: 13)
        window("multiselect-min", minimum, size: CGSize(width: 1120, height: 640))

        // The same keys' hold, which none of them has: the hold editor, applied to all four.
        let hold = await model(f, key: 13)
        hold.session?.select(keys: [13, 14, 15, 16], anchor: 13)
        hold.session?.select(key: 13, slot: .hold)
        window("multiselect-hold", hold)

        // ⇧-click across the halves on Sym+Num, and the picker's "N keys" target.
        let picking = await model(f, layer: 1, key: 9)
        picking.session?.select(keys: [9, 10, 11, 35, 36, 37], anchor: 9)
        picking.openKeycodePicker(prefilled: "esc")
        window("multiselect-picker", picking)

        // Copy Layer To ▸ on Sym+Num's context menu. Real menus can't render offscreen, so this draws their items.
        let menu = await model(f, layer: 1)
        let menus = [
            SnapshotOverlay.menu(size: CGSize(width: 200, height: 0), at: CGPoint(x: 150, y: 190)) { layerMenu(open: "Copy Layer To") },
            SnapshotOverlay.menu(size: CGSize(width: 170, height: 0), at: CGPoint(x: 346, y: 318)) { copyLayerMenu },
        ]
        window("layers-copy-menu", menu, overlays: menus)
        return scenes
    }

    private static var copyLayerMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(["Layer 0 · Main", "Layer 2 · Brd+Sys"], id: \.self) { item in
                Text(item).padding(.horizontal, 8).frame(height: 22)
            }
            Divider().padding(.vertical, 4)
            Text("New Layer").padding(.horizontal, 8).frame(height: 22)
        }
        .padding(5)
    }
}
