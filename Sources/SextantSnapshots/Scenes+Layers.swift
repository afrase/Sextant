import SextantApplication
import SextantDomain
import SextantUI
import SwiftUI

extension Scenes {
    /// Layers and the Lighting lens (spec §3.6, §3.8, §6.1, §6.2).
    static func layers(_ f: Fixtures) async -> [SnapshotScene] {
        let rename = await model(f, layer: 1)
        let menu = await model(f, layer: 1)
        let summary = await model(f, layer: 1)
        let lighting = await model(f, layer: 2)
        let lightingMin = await model(f, layer: 2)
        // Edits come after every model has loaded, so their autosaves can't leak into another scene.
        rename.startRenaming(layer: 1)
        let brush = KeyboardLayout.defaultSwatch.first ?? HexColor(red: 1, green: 0, blue: 0)
        for m in [lighting, lightingMin] {
            m.lens = .lighting
            m.session?.paint(brush, keys: [14, 15, 16, 20], layer: 2)
        }
        // Live presses light in every lens (spec §2.2).
        lightingMin.pressedKeys.update([15, 31])

        func window(_ name: String, _ model: LayoutWindowModel, size: CGSize = full, overlays: [SnapshotOverlay] = []) -> [SnapshotScene] {
            SnapshotScene.pair(name, size: size, overlays: overlays) { LayoutWindow(model: model, layoutID: .constant(f.entry.id)) }
        }
        // The context menu on Sym+Num with Colour ▸ open. Real menus can't render offscreen, so this draws their items.
        let menus = [
            SnapshotOverlay.menu(size: CGSize(width: 200, height: 0), at: CGPoint(x: 150, y: 190)) { layerMenu },
            SnapshotOverlay.menu(size: CGSize(width: 150, height: 0), at: CGPoint(x: 346, y: 222)) { colourMenu },
        ]
        return window("layers-rename", rename) + window("layers-colour-menu", menu, overlays: menus)
            + window("layers-summary", summary) + window("lighting", lighting)
            + [
                SnapshotScene("lighting-min-light", size: CGSize(width: 1120, height: 640)) {
                    LayoutWindow(model: lightingMin, layoutID: .constant(f.entry.id))
                }
            ]
    }

    private static var layerMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            let items = [
                "Rename…", "Colour", "-", "Duplicate", "Move Up", "Move Down", "-", "Copy Layer To…", "Clear Layer…", "Delete Layer…",
            ]
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                if item == "-" {
                    Divider().padding(.vertical, 4)
                } else {
                    HStack {
                        Text(item)
                        Spacer()
                        if item == "Colour" { Image(systemName: "chevron.right").font(.caption) }
                    }
                    .foregroundStyle(item == "Copy Layer To…" ? .tertiary : .primary)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(item == "Colour" ? Color.accentColor.opacity(0.85) : .clear, in: .rect(cornerRadius: 5))
                }
            }
        }
        .padding(5)
    }

    private static var colourMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(KeyboardLayout.defaultSwatch, id: \.self) { color in
                // Sym+Num's #00F0FF isn't a swatch, so nothing is ticked.
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3).fill(color.color).frame(width: 12, height: 12)
                    Text(verbatim: color.hex).monospacedDigit()
                }
                .padding(.leading, 26)
                .frame(height: 22)
            }
            Divider().padding(.vertical, 4)
            Text("Custom…").padding(.horizontal, 26).frame(height: 22)
            Text("No Colour").padding(.horizontal, 26).frame(height: 22)
        }
        .padding(5)
    }
}
