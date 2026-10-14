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
            let size = CGSize(width: width + 80, height: hudHeight(layout, width: width) + 80)
            return SnapshotScene.pair(name, size: size, chrome: .content) {
                HUDView(layout: layout, layer: layer, holder: holder, pressed: pressed, width: width, tints: tints)
            }
        }
        scenes += hud("hud-symnum", width: 696, layer: 1, holder: enter, pressed: [24, 13])
        scenes += hud("hud-symnum-tinted", width: 696, layer: 1, holder: enter, pressed: [24], tints: true)
        scenes += hud("hud-brdsys-small", width: 522, layer: 2, holder: KeyRef(layer: 0, index: 51), pressed: [51])
        scenes += hud("hud-brdsys-large", width: 870, layer: 2, holder: KeyRef(layer: 0, index: 51), pressed: [51, 13])
        scenes += hud("hud-symnum-locked", width: 696, layer: 1, holder: nil, pressed: [])
        scenes.append(
            SnapshotScene(
                "hud-reduce-transparency-light", size: CGSize(width: 776, height: hudHeight(layout, width: 696) + 80), chrome: .content
            ) {
                HUDView(layout: layout, layer: 1, holder: enter, pressed: [24], width: 696, tints: true)
                    .environment(\._accessibilityReduceTransparency, true)
            })
        scenes += SnapshotScene.pair("hud-pill", size: CGSize(width: 260, height: 72), chrome: .content) {
            HUDPill(layout: layout, layer: 1)
        }
        scenes += SnapshotScene.pair("hud-pill-tinted", size: CGSize(width: 260, height: 72), chrome: .content) {
            HUDPill(layout: layout, layer: 2, tints: true)
        }
        return scenes
    }

    /// The HUD's height at `width`: padding, the 24 pt header, spacing, and the map at the board's proportions.
    private static func hudHeight(_ layout: KeyboardLayout, width: CGFloat) -> CGFloat {
        let bounds = EditSession.geometry(of: layout).bounds
        return 20 + 24 + 14 + ((width - 40) * bounds.height / bounds.width).rounded() + 20
    }
}
