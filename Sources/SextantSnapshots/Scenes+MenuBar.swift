import AppKit
import SextantApplication
import SextantDomain
import SextantUI
import SwiftUI

// The menu bar extra (spec §8.3, ADR 0049): its panel as a plain view in each state, and its label's images. Both are
// drawn from values, so nothing here touches a keyboard or puts anything in the menu bar.

extension Scenes {
    static func menuBar(_ f: Fixtures) async -> [SnapshotScene] {
        var scenes: [SnapshotScene] = []
        guard let layout = await model(f).session?.layout else { return scenes }
        let running = "\(layout.title), revision 1"
        let twelve = twelveLayers(layout)
        let shortcuts = Dictionary(uniqueKeysWithValues: (0..<10).map { ($0, "⌃⌥\($0)") })
        let panels: [(String, MenuBarPanelState, Bool)] = [
            // Brd+Sys, reached by holding Space (51), with Space and a key it defines (13) down.
            ("tiles", MenuBarPanelState(keyboard: .live, running: running, layout: layout, layer: 2, pressed: [13, 51]), true),
            (
                "list",
                MenuBarPanelState(keyboard: .live, running: "Twelve layers, revision 4", layout: twelve, layer: 5, shortcuts: shortcuts),
                true
            ),
            ("no-keyboard", MenuBarPanelState(keyboard: .none), true),
            ("live-off", MenuBarPanelState(keyboard: .liveOff, running: running, layout: layout), true),
            (
                "flashing",
                MenuBarPanelState(keyboard: .flashMode, flash: MenuBarPanelState.Flash(title: layout.title, progress: 0.65)), true
            ),
            ("held", MenuBarPanelState(keyboard: .heldByAnotherApp, running: "KlgM7/40xJ7M"), false),
            (
                "unknown-layout",
                MenuBarPanelState(
                    keyboard: .live, running: "Q9x2/aa11", layer: 0,
                    layerNote: "Sextant doesn’t have the keyboard’s layout, so it can move it only to layer 0."), false
            ),
            ("secure-input", MenuBarPanelState(keyboard: .live, running: running, layout: layout, layer: 1, isSecureInputOn: true), false),
        ]
        for (name, state, both) in panels {
            let size = NSHostingView(rootView: MenuBarPanelContent(state: state)).fittingSize
            let make = { MenuBarPanelContent(state: state) }
            if both {
                scenes += SnapshotScene.pair("menubar-panel-\(name)", size: size, chrome: .content) { make() }
            } else {
                scenes.append(SnapshotScene("menubar-panel-\(name)-light", size: size, chrome: .content) { make() })
            }
        }
        scenes += SnapshotScene.pair("menubar-labels", size: CGSize(width: 420, height: 8 * 94 + 16), chrome: .content) {
            labels(layout)
        }
        return scenes
    }

    /// The user's layout grown to twelve layers, past the four that get tiles.
    static func twelveLayers(_ layout: KeyboardLayout) -> KeyboardLayout {
        var layout = layout
        layout.title = "Twelve layers"
        let names = ["Nav", "Mouse", "Media", "Fn", "Numpad", "Code", "Arrows", "Gaming", "Symbols 2"]
        let colors = ["#FF9500", "#AF52DE", "#FF2D55", "#5856D6", "#34C759", "#FFCC00", "#5AC8FA", "#FF3B30", nil]
        for (name, color) in zip(names, colors) {
            layout.layers.append(Layer(title: name, color: color.flatMap { HexColor(hex: $0) }, keys: layout.layers[1].keys))
        }
        return layout
    }

    /// The label in each state, at its real size and at 4×, on a menu bar strip of the scene's appearance: the menu bar
    /// tints the template images, and draws the color-dot one in its own appearance's label color.
    private static func labels(_ layout: KeyboardLayout) -> some View {
        let states: [(String, MenuBarLabelState)] = [
            ("No keyboard", MenuBarLabelState(connection: .noKeyboard, layer: nil, progress: nil)),
            ("Live View off", MenuBarLabelState(connection: .liveOff(keyboard), layer: nil, progress: nil)),
            ("Layer 0", MenuBarLabelState(connection: .connected(keyboard), layer: 0, progress: nil)),
            ("Layer 2", MenuBarLabelState(connection: .connected(keyboard), layer: 2, progress: nil)),
            ("Layer 12", MenuBarLabelState(connection: .connected(keyboard), layer: 12, progress: nil)),
            ("Flashing 35%", MenuBarLabelState(connection: .bootloader(bootloader), layer: nil, progress: 0.35)),
            ("Flashing 100%", MenuBarLabelState(connection: .bootloader(bootloader), layer: nil, progress: 1)),
            ("Color dot", MenuBarLabelState(connection: .connected(keyboard), layer: 1, progress: nil, dot: layout.layers[1].color)),
        ]
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(states.indices, id: \.self) { n in
                HStack(spacing: 12) {
                    Text(verbatim: states[n].0).font(.caption).frame(width: 90, alignment: .leading)
                    LabelStrip(image: states[n].1.image, scale: 1)
                    LabelStrip(image: states[n].1.image, scale: 4)
                }
            }
        }
        .padding(8)
    }

    private static let keyboard = KeyboardDevice(id: 1, productID: 0x1977, serial: "KlgM7/40xJ7M")
    private static let bootloader = BootloaderDevice(id: 9, productID: 0x0791, kind: .stm32, version: 0x0200)
}

/// A strip of menu bar under one label image, in the scene's appearance; at a scale above 1 the image is drawn that much
/// bigger, from its vector drawing.
private struct LabelStrip: View {
    var image: NSImage
    var scale: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Image(nsImage: image).resizable()
            .frame(width: image.size.width * scale, height: image.size.height * scale)
            .foregroundStyle(scheme == .dark ? Color.white : .black)
            .frame(width: 80 * scale / 2 + 40, height: 22 * scale)
            .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.93))
    }
}
