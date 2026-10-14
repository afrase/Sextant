import SextantApplication
import SextantDomain
import SwiftUI

/// One layer of the layout on the keyboard, read-only, with the keys held down lit (ADR 0048): the menu bar's mini map
/// and the overlay HUD's board (spec §8.3, §8.4). It fits the space it gets. Caps the layer defines are ringed in its
/// color, as on the board; VoiceOver reads it as one element.
public struct LayerMap: View {
    var layout: KeyboardLayout
    var layer: Int
    /// Indices of the keys held down; pass none while secure input is on.
    var pressed: Set<Int>

    public init(layout: KeyboardLayout, layer: Int, pressed: Set<Int> = []) {
        self.layout = layout
        self.layer = layer
        self.pressed = pressed
    }

    public var body: some View {
        let geometry = EditSession.geometry(of: layout)
        GeometryReader { proxy in
            // The board's own proportions (cap = pitch / 1.11, spacing 0.11 cap), scaled to fit.
            let pitch = min(proxy.size.width / geometry.bounds.width, proxy.size.height / geometry.bounds.height)
            let cap = max(pitch / 1.11, 1)
            let board = geometry.layout(keySize: cap, spacing: cap * 0.11)
            ZStack(alignment: .topLeading) {
                if let kind = layout.navigator?.kind, let nav = board.navigator {
                    NavigatorDisc(diameter: nav.diameter, kind: kind).position(nav.center)
                }
                BoardCanvas(layout: board) { frame in
                    KeyCap(
                        model: KeyCapModel(layout: layout, layer: layer, index: frame.index), u: cap, height: frame.size.height,
                        isPressed: pressed.contains(frame.index)
                    )
                    .equatable()
                }
            }
            .frame(width: board.size.width, height: board.size.height)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .aspectRatio(geometry.bounds.width / geometry.bounds.height, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityText(layout: layout, layer: layer, pressed: pressed))
    }

    /// "Sym+Num layer, keys down k24": positions only, as the Device popover says them.
    static func accessibilityText(layout: KeyboardLayout, layer: Int, pressed: Set<Int>) -> String {
        let name = layout.layers[safe: layer]?.title ?? layer.formatted()
        guard !pressed.isEmpty else { return String(localized: "\(name) layer, no keys down") }
        let keys = pressed.sorted().map { "k\($0)" }.joined(separator: " ")
        return String(localized: "\(name) layer, keys down \(keys)")
    }
}
