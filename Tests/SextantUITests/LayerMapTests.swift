import SextantApplication
import SextantDomain
import SnapshotTesting
import SwiftUI
import Testing

@testable import SextantUI

/// The read-only layer map the menu bar and the overlay reuse (ADR 0048).
@MainActor
struct LayerMapTests {
    @Test func voiceOverReadsTheLayerAndTheKeysDown() throws {
        let layout = try KeyboardLayout(oryxJSON: #require(userLayoutData))
        #expect(LayerMap.accessibilityText(layout: layout, layer: 1, pressed: [24]) == "Sym+Num layer, keys down k24")
        #expect(LayerMap.accessibilityText(layout: layout, layer: 2, pressed: [51, 13]) == "Brd+Sys layer, keys down k13 k51")
        #expect(LayerMap.accessibilityText(layout: layout, layer: 0, pressed: []) == "Main layer, no keys down")
    }

    @Test(
        .disabled(if: skipsPixelSnapshots, "the references are rendered on the developer's macOS"), arguments: [ColorScheme.light, .dark])
    func brdSysWithKeysDown(scheme: ColorScheme) throws {
        let layout = try KeyboardLayout(oryxJSON: #require(userLayoutData))
        let view = LayerMap(layout: layout, layer: 2, pressed: [13, 51]).frame(width: 336, height: 136).padding(12)
            .background(Tokens.benchBase.color).environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try #require(renderer.nsImage)
        assertSnapshot(of: image, as: .image(precision: 0.99, perceptualPrecision: 0.98), named: scheme == .dark ? "dark" : "light")
    }
}

/// Keyboard ▸ Move Keyboard to Layer's heading (ADR 0048), over a stand-in keyboard: nothing here writes to one.
@MainActor
struct MoveKeyboardToLayerMenuTests {
    @Test func theHeadingSaysWhyItemsAreDisabledOrWhyOnlyLayerZeroShows() async throws {
        let keyboard = UnknownKeyboard()
        let live = LiveSession(watcher: keyboard, link: keyboard, secureInputProbe: { false })
        let store = MemoryLibrary()
        let onKeyboard = OnKeyboard(library: Library(store: store), store: store, live: live)
        live.start()
        onKeyboard.start()
        for _ in 0..<200 where live.connection == .noKeyboard { try await Task.sleep(for: .milliseconds(10)) }
        let off = MoveKeyboardToLayerMenu.heading(onKeyboard)
        #expect(off?.text == "Turn on Live View to move the keyboard’s layer." && off?.enabled == false)

        live.startLive()
        for _ in 0..<300 where !live.canSend { try await Task.sleep(for: .milliseconds(10)) }
        let unknown = MoveKeyboardToLayerMenu.heading(onKeyboard)
        #expect(unknown?.text == "Sextant doesn’t have the keyboard’s layout, so it can move it only to layer 0.")
        #expect(unknown?.enabled == true, "layer 0 can still be chosen")
    }
}

/// A keyboard running a layout the library doesn't hold; once Live View starts, its session reports layer 0 and stays
/// open.
private struct UnknownKeyboard: DeviceWatcher, KeyboardLink {
    func events(for board: BoardDefinition) -> AsyncStream<DeviceEvent> {
        AsyncStream { $0.yield(.attached(.keyboard(KeyboardDevice(id: 1, productID: 0x1977, serial: "Q9x2/aa11")))) }
    }

    func session(with device: KeyboardDevice, board: BoardDefinition, commands: AsyncStream<KeyboardCommand>) -> AsyncStream<LiveEvent> {
        AsyncStream { $0.yield(.layer(0)) }
    }
}
