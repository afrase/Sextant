import SextantApplication
import SextantDomain
import SextantUI
import SwiftUI

// The overlay HUD's content (ADR 0050), drawn as plain views: the real panel floats over other apps, so it never shows
// here. The keyboard is the user's layout; nothing here touches hardware.

extension Scenes {
    static func overlay(_ f: Fixtures) async -> [SnapshotScene] {
        var scenes: [SnapshotScene] = []
        guard let layout = await model(f).session?.layout else { return scenes }
        // ⏎ (key 24) holds Sym+Num, with a key on it (13) held too. Widths: Medium, Small and Large on a 1512 pt screen.
        let enter = KeyRef(layer: 0, index: 24)
        func hud(_ name: String, width: CGFloat, layer: Int, holder: KeyRef?, pressed: Set<Int>, tints: Bool = false) -> [SnapshotScene] {
            let size = CGSize(width: width + 80, height: HUDView.height(layout: layout, width: width) + 80)
            return SnapshotScene.pair(name, size: size, chrome: .content) {
                HUDView(layout: layout, layer: layer, holder: holder, pressed: pressed, width: width, tints: tints)
            }
        }
        scenes += hud("hud-symnum", width: 696, layer: 1, holder: enter, pressed: [24, 13])
        scenes += hud("hud-symnum-tinted", width: 696, layer: 1, holder: enter, pressed: [24], tints: true)
        scenes += hud("hud-brdsys-small", width: 522, layer: 2, holder: KeyRef(layer: 0, index: 51), pressed: [51])
        scenes += hud("hud-brdsys-large", width: 870, layer: 2, holder: KeyRef(layer: 0, index: 51), pressed: [51, 13])
        // Small on a 1024 pt screen: the hint gives way before the name and the state truncate.
        scenes += hud("hud-brdsys-small-narrow", width: 353, layer: 2, holder: KeyRef(layer: 0, index: 51), pressed: [51])
        scenes += hud("hud-symnum-locked", width: 696, layer: 1, holder: nil, pressed: [])
        // A plain MO key holding it: its cap would repeat the layer's name, so the state reads "held".
        var momentary = layout
        momentary.layers[0].keys[24] = Key(tap: .momentary(1))
        scenes += SnapshotScene.pair(
            "hud-symnum-mo", size: CGSize(width: 776, height: HUDView.height(layout: layout, width: 696) + 80), chrome: .content
        ) {
            HUDView(layout: momentary, layer: 1, holder: enter, pressed: [24], width: 696)
        }
        let opaqueSize = CGSize(width: 776, height: HUDView.height(layout: layout, width: 696) + 80)
        scenes.append(
            SnapshotScene("hud-reduce-transparency-light", size: opaqueSize, chrome: .content) {
                HUDView(layout: layout, layer: 1, holder: enter, pressed: [24], width: 696, tints: true)
                    .environment(\._accessibilityReduceTransparency, true)
            })
        scenes += SnapshotScene.pair("hud-increase-contrast", size: opaqueSize, chrome: .content) {
            HUDView(layout: layout, layer: 1, holder: enter, pressed: [24], width: 696, tints: true)
                .environment(\._colorSchemeContrast, .increased)
        }
        scenes += SnapshotScene.pair("hud-pill", size: CGSize(width: 260, height: 72), chrome: .content) {
            HUDPill(layout: layout, layer: 1)
        }
        scenes += SnapshotScene.pair("hud-pill-tinted", size: CGSize(width: 260, height: 72), chrome: .content) {
            HUDPill(layout: layout, layer: 2, tints: true)
        }
        return scenes
    }
}
