import Foundation
import SextantApplication
import SextantDomain
import SextantStorage
import SextantUI
import SwiftUI

// The layer map, Settings › Keyboard's layer shortcuts and the Device popover's Move Keyboard to Layer (ADR 0048). The
// hot keys are a stand-in that registers nothing, and the keyboard is a stand-in too: nothing here touches hardware or
// takes a key system-wide.

extension Scenes {
    static func layerShortcuts(_ f: Fixtures) async -> [SnapshotScene] {
        var scenes: [SnapshotScene] = []
        guard let layout = await model(f).session?.layout else { return scenes }
        // Brd+Sys with Space (51) and a key it defines (13) held: the menu bar's mini map, and the HUD's larger board.
        scenes += SnapshotScene.pair("layer-map-brdsys", size: CGSize(width: 360, height: 160), chrome: .content) {
            LayerMap(layout: layout, layer: 2, pressed: [13, 51]).padding(12)
        }
        scenes += SnapshotScene.pair("layer-map-symnum-hud", size: CGSize(width: 680, height: 290), chrome: .content) {
            LayerMap(layout: layout, layer: 1, pressed: [24]).padding(20)
        }

        // On, with ⌃⌥3 held by another app, ⌃⌥5 a macOS shortcut, and a press made while Live View was off.
        let (on, hotKeys) = await layerShortcuts(on: true)
        hotKeys.conflicting = [3: .inUse, 5: .takenBySystem]
        on.shortcutsChanged()
        hotKeys.press(2)
        scenes += SnapshotScene.pair(
            "settings-keyboard-shortcuts", size: CGSize(width: 520, height: 1000), chrome: .window(title: "Keyboard")
        ) {
            KeyboardSettings(layerShortcuts: on)
        }

        // The Device popover over a keyboard paired on Sym+Num, running the user's layout.
        let keyboard = PairedKeyboard()
        let live = LiveSession(watcher: keyboard, link: keyboard, secureInputProbe: { false })
        live.start()
        live.startLive()
        guard let root = await f.windowModel().library.location(of: f.entry.id)?.deletingLastPathComponent() else { return scenes }
        let store = PackageLibrary(root: root)
        let library = Library(store: store)
        let onKeyboard = OnKeyboard(library: library, store: store, live: live)
        await library.refresh()
        onKeyboard.start()
        let window = LayoutWindowModel(library: library, live: live, onKeyboard: onKeyboard)
        await window.open(f.entry.id)
        window.buildFlash = await idleBuildFlash(window)
        Task { await window.followKeyboard() }
        for _ in 0..<250 where !live.canSend || onKeyboard.running == nil || window.session?.selection.layer != 1 {
            try? await Task.sleep(for: .milliseconds(20))
        }
        scenes += SnapshotScene.pair(
            "device-popover-move", size: full,
            overlays: [
                .popover(size: CGSize(width: 360, height: 0), anchor: CGRect(x: 560, y: 14, width: 150, height: 26)) {
                    DevicePopover(model: window)
                }
            ]
        ) { LayoutWindow(model: window, layoutID: .constant(f.entry.id)) }
        return scenes
    }

    /// The pane's real `LayerShortcuts` over stand-in hot keys, and a keyboard plugged in with Live View off.
    static func layerShortcuts(on: Bool) async -> (LayerShortcuts, some HotKeys & StandIn) {
        let keyboard = PairedKeyboard()
        let live = LiveSession(watcher: keyboard, link: keyboard, secureInputProbe: { false })
        live.start()
        for _ in 0..<50 where live.connection == .noKeyboard { try? await Task.sleep(for: .milliseconds(10)) }
        let store = PackageLibrary(root: FileManager.default.temporaryDirectory.appending(path: "sextant-unused"))
        let hotKeys = StandInHotKeys()
        let shortcuts = LayerShortcuts(
            hotKeys: hotKeys, onKeyboard: OnKeyboard(library: Library(store: store), store: store, live: live), isOn: on)
        shortcuts.start()
        return (shortcuts, hotKeys)
    }
}

/// Hot keys a scene can set conflicts on and press.
@MainActor
protocol StandIn: AnyObject {
    var conflicting: [Int: HotKeyConflict] { get set }
    func press(_ layer: Int)
}

/// ⌃⌥0–⌃⌥9, registered nowhere; `press` stands in for the user pressing one.
@MainActor
private final class StandInHotKeys: HotKeys, StandIn {
    private var onPress: (@MainActor (Int) -> Void)?
    var conflicting: [Int: HotKeyConflict] = [:]

    func register(layers: Range<Int>, onPress: @escaping @MainActor (Int) -> Void) { self.onPress = onPress }
    func unregister() { onPress = nil }
    func setPaused(_ paused: Bool) {}
    func shortcut(forLayer layer: Int) -> HotKeyShortcut? {
        HotKeyShortcut(keyCode: 0, modifiers: [.control, .option], text: "⌃⌥\(layer)", keyEquivalent: "\(layer)")
    }
    func conflicts() -> [Int: HotKeyConflict] { conflicting }
    func press(_ layer: Int) { onPress?(layer) }
}

/// The user's keyboard, present from the start; once Live View starts, its session reports Sym+Num and stays open.
private struct PairedKeyboard: DeviceWatcher, KeyboardLink {
    func events(for board: BoardDefinition) -> AsyncStream<DeviceEvent> {
        AsyncStream { $0.yield(.attached(.keyboard(KeyboardDevice(id: 1, productID: 0x1977, serial: "KlgM7/40xJ7M")))) }
    }

    func session(with device: KeyboardDevice, board: BoardDefinition, commands: AsyncStream<KeyboardCommand>) -> AsyncStream<LiveEvent> {
        AsyncStream { $0.yield(.layer(1)) }
    }
}
