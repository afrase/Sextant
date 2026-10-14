import AppKit
import SextantApplication
import SextantDomain
import SnapshotTesting
import SwiftUI
import Synchronization
import Testing

@testable import SextantUI

/// The menu bar extra (spec §8.3, ADR 0049): its label, its panel and where its requests go. The keyboard is a stand-in;
/// nothing here writes to one or puts anything in the menu bar.
@MainActor
struct MenuBarTests {
    private let keyboard = KeyboardDevice(id: 1, productID: 0x1977, serial: "KlgM7/40xJ7M")

    // MARK: Label

    @Test func theLabelShowsTheLayerOnlyWhenTheKeyboardReportsOne() {
        let none = MenuBarLabelState(connection: .noKeyboard, layer: nil, progress: nil)
        #expect(none.isDimmed && none.layer == nil && none.progress == nil)
        let off = MenuBarLabelState(connection: .liveOff(keyboard), layer: nil, progress: nil)
        #expect(!off.isDimmed && off.layer == nil)
        let connecting = MenuBarLabelState(connection: .connected(keyboard), layer: nil, progress: nil)
        #expect(!connecting.isDimmed && connecting.layer == nil)
        let live = MenuBarLabelState(connection: .connected(keyboard), layer: 2, progress: nil)
        #expect(live.layer == 2 && !live.isDimmed && live.accessibilityText == "Sextant, keyboard on layer 2")
        // A layer from a session that is no longer paired is never shown.
        #expect(MenuBarLabelState(connection: .heldByAnotherApp(keyboard), layer: 2, progress: nil).layer == nil)
    }

    /// The label over the app's live session shows a layer only while a session is paired: not the last one's while the
    /// next pairs, after a session ended.
    @Test func theLabelDropsTheLayerWhenTheSessionEnds() async throws {
        let fake = StandInKeyboard(serial: "KlgM7/40xJ7M", events: [.layer(2), .ended(.io("unplugged mid-write"))])
        let (live, onKeyboard, library) = Self.session(fake)
        live.startLive()
        #expect(await eventually { live.activeLayer == 2 && !live.canSend && live.connection == .connected(keyboard) })
        let label = MenuBarLabelState(live: live, onKeyboard: onKeyboard, showsColor: true)
        #expect(label.layer == nil && label.dot == nil && label.accessibilityText == "Sextant, keyboard connected")
        let panel = MenuBarPanelState(live: live, onKeyboard: onKeyboard, shortcuts: nil, library: library, buildTarget: nil)
        #expect(panel.keyboard == .connecting && panel.layer == nil && !panel.canMove)
        #expect(panel.status == "Connected · connecting…")
    }

    /// A session pairs on key events before it reports a layer: it can take a move, so the panel is live with no layer.
    @Test func aSessionPairedBeforeItsFirstLayerIsLive() async throws {
        let fake = StandInKeyboard(serial: "KlgM7/40xJ7M", events: [.keyDown(row: 0, column: 0)])
        let (live, onKeyboard, library) = Self.session(fake)
        live.startLive()
        #expect(await eventually { live.canSend && live.activeLayer == nil })
        let panel = MenuBarPanelState(live: live, onKeyboard: onKeyboard, shortcuts: nil, library: library, buildTarget: nil)
        #expect(panel.keyboard == .live && panel.layer == nil && panel.canMove && panel.status == "Connected · Live View on")
        #expect(MenuBarLabelState(live: live, onKeyboard: onKeyboard, showsColor: false).layer == nil)
    }

    @Test func aFlashFillsTheArcInFivePercentSteps() {
        let bootloader = BootloaderDevice(id: 9, productID: 0x0791, kind: .stm32, version: 0x0200)
        let flashing = MenuBarLabelState(connection: .bootloader(bootloader), layer: nil, progress: 0.37)
        #expect(flashing.progress == 0.35 && flashing.layer == nil && !flashing.isDimmed)
        #expect(flashing.accessibilityText == "Sextant, flashing the keyboard, 35 percent")
        #expect(MenuBarLabelState(connection: .bootloader(bootloader), layer: nil, progress: 1.2).progress == 1)
    }

    @Test func theLabelIsATemplateImageUnlessTheColorDotIsOn() throws {
        let plain = MenuBarLabelState(connection: .connected(keyboard), layer: 1, progress: nil)
        #expect(plain.image.isTemplate)
        let color = try #require(HexColor(hex: "#00F0FF"))
        let dotted = MenuBarLabelState(connection: .connected(keyboard), layer: 1, progress: nil, dot: color)
        #expect(!dotted.image.isTemplate && dotted.dot == color)
        #expect(dotted.image.size.width > plain.image.size.width)
        // No layer, no dot: the dot belongs to the number.
        #expect(MenuBarLabelState(connection: .liveOff(keyboard), layer: nil, progress: nil, dot: color).dot == nil)
        // The number is drawn into the image, so two digits make it wider than one.
        let twelve = MenuBarLabelState(connection: .connected(keyboard), layer: 12, progress: nil)
        #expect(twelve.image.size.width > plain.image.size.width)
        #expect(MenuBarLabelState(connection: .noKeyboard, layer: nil, progress: nil).image.size.width == 16)
    }

    /// The label's drawing, 4× on a light menu bar as the system draws the image: the dimmed mark, layers 2 and 12, and a
    /// flash at 35% and done.
    @Test(.disabled(if: skipsPixelSnapshots, "the references are rendered on the developer's macOS"))
    func labelImages() throws {
        let bootloader = BootloaderDevice(id: 9, productID: 0x0791, kind: .stm32, version: 0x0200)
        let images = [
            MenuBarLabelState(connection: .noKeyboard, layer: nil, progress: nil),
            MenuBarLabelState(connection: .connected(keyboard), layer: 2, progress: nil),
            MenuBarLabelState(connection: .connected(keyboard), layer: 12, progress: nil),
            MenuBarLabelState(connection: .bootloader(bootloader), layer: nil, progress: 0.35),
            MenuBarLabelState(connection: .bootloader(bootloader), layer: nil, progress: 1),
        ].map(\.image)
        // Drawn straight into an 8-bit sRGB bitmap at 4×, from the images' own drawing, so the strokes stay sharp.
        let scale: CGFloat = 4
        let size = CGSize(width: 48, height: CGFloat(images.count) * 24 + 4)
        let sRGB = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
                space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(gray: 0.93, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale))
        context.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        for (n, image) in images.enumerated() {
            image.draw(in: CGRect(origin: CGPoint(x: 4, y: size.height - CGFloat(n + 1) * 24), size: image.size))
        }
        NSGraphicsContext.restoreGraphicsState()
        let bitmap = try #require(context.makeImage())
        let image = NSImage(cgImage: bitmap, size: NSSize(width: bitmap.width, height: bitmap.height))
        assertSnapshot(of: image, as: .image(precision: 0.99, perceptualPrecision: 0.98), named: "light")
    }

    // MARK: Panel

    @Test func tilesUpToFourLayersThenRows() throws {
        let layout = try KeyboardLayout(oryxJSON: #require(userLayoutData))
        #expect(MenuBarPanelState(keyboard: .live, layout: layout, layer: 0).usesTiles, "the user's three layers")
        #expect(!MenuBarPanelState(keyboard: .live, layout: Self.layout(layout, layers: 12), layer: 0).usesTiles)
        #expect(MenuBarPanelState(keyboard: .live, layout: Self.layout(layout, layers: 4), layer: 0).usesTiles)
        #expect(!MenuBarPanelState(keyboard: .live, layout: Self.layout(layout, layers: 5), layer: 0).usesTiles)
        // A layout Sextant doesn't have offers layer 0 alone, as a tile.
        let unknown = MenuBarPanelState(keyboard: .live, layer: 0)
        #expect(unknown.layers.map(\.index) == [0] && unknown.usesTiles)
        // With Live View off there is nothing to choose from.
        #expect(MenuBarPanelState(keyboard: .liveOff, layout: layout).layers.isEmpty)
    }

    /// The heading names how the layer is reached, or the layer itself when the panel doesn't list it.
    @Test func theHeadingNamesALayerThePanelDoesntList() throws {
        let layout = try KeyboardLayout(oryxJSON: #require(userLayoutData))
        #expect(MenuBarPanelState(keyboard: .live, layer: 3).layerDetail == "On layer 3", "a layout Sextant doesn't have")
        #expect(MenuBarPanelState(keyboard: .live, layer: 0).layerDetail == nil)
        let known = MenuBarPanelState(keyboard: .live, layout: layout, layer: 2)
        #expect(known.layerDetail == known.activator && known.activator != nil)
    }

    @Test(.enabled(if: referenceExamples != nil, "needs SEXTANT_REFERENCE"))
    func jrgqmsTwelveLayersAreRows() throws {
        let layout = try KeyboardLayout(oryxJSON: Data(contentsOf: exampleURL("voyager-JRGQm.json")))
        #expect(layout.layers.count == 12)
        #expect(!MenuBarPanelState(keyboard: .live, layout: layout, layer: 3).usesTiles)
    }

    /// Spec §13.3: a `.window` menu bar extra stays under 520 pt tall, even with every layer a move can reach.
    @Test func thePanelStaysUnder520Points() throws {
        let layout = try KeyboardLayout(oryxJSON: #require(userLayoutData))
        let shortcuts = Dictionary(uniqueKeysWithValues: (0..<10).map { ($0, "⌃⌥\($0)") })
        let states = [
            MenuBarPanelState(keyboard: .live, running: "My MacOS Layout, revision 12", layout: layout, layer: 2, pressed: [13, 51]),
            MenuBarPanelState(
                keyboard: .live, running: "Thirty-two layers, revision 3", layout: Self.layout(layout, layers: 40), layer: 31,
                shortcuts: shortcuts, isSecureInputOn: true),
            MenuBarPanelState(
                keyboard: .connecting, running: "Q9x2/aa11", layer: nil,
                layerNote: "Sextant doesn’t have the keyboard’s layout, so it can move it only to layer 0."),
            MenuBarPanelState(keyboard: .liveOff, running: "My MacOS Layout, revision 12", layout: layout),
            MenuBarPanelState(keyboard: .flashMode, flash: MenuBarPanelState.Flash(title: "My MacOS Layout", progress: 0.4)),
        ]
        for state in states {
            let size = NSHostingView(rootView: MenuBarPanelContent(state: state)).fittingSize
            #expect(size.width == 360)
            #expect(size.height < 520 && size.height > 150, "\(state.keyboard): \(size.height) pt")
        }
        // A move reaches the first 32 layers only (ADR 0038).
        #expect(MenuBarPanelState(keyboard: .live, layout: Self.layout(layout, layers: 40), layer: 0).layers.count == 32)
    }

    /// The panel over the app's live session, driven through its own controls: showing the panel and its label pairs
    /// with nothing, Turn On Live View starts Live View, the user's layout gets tiles with the global shortcuts' hints,
    /// and a tile moves the keyboard through Move Keyboard to Layer. Build & Flash… names the layout it opens.
    @Test func thePanelFollowsTheKeyboardAndMovesItsLayer() async throws {
        let fake = StandInKeyboard(serial: "KlgM7/40xJ7M")
        let (live, onKeyboard, library) = Self.session(fake)
        let entry = try await library.importOryxJSON(#require(userLayoutData))
        let shortcuts = LayerShortcuts(hotKeys: SilentHotKeys(), onKeyboard: onKeyboard, isOn: true)
        shortcuts.start()
        #expect(await eventually { onKeyboard.running != nil })
        let router = WindowRouter(
            library: library, onKeyboard: onKeyboard, live: live, presence: AppPresence(apply: { _ in }), activate: {})
        // In windows that are never ordered in, so the views appear without anything on screen.
        let hosts: [NSWindow] = [
            NSHostingView(
                rootView: MenuBarPanel(live: live, onKeyboard: onKeyboard, shortcuts: shortcuts, library: library, windows: router)),
            NSHostingView(rootView: MenuBarLabel(live: live, onKeyboard: onKeyboard)),
        ].map { view in
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 360, height: 500), styleMask: .borderless, backing: .buffered, defer: true)
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            return window
        }
        let state = {
            MenuBarPanelState(live: live, onKeyboard: onKeyboard, shortcuts: shortcuts, library: library, buildTarget: router.target)
        }
        let off = state()
        #expect(off.keyboard == .liveOff && off.layers.isEmpty && off.running == "My MacOS Layout, revision 1")
        #expect(off.buildTarget == "My MacOS Layout")
        try await Task.sleep(for: .milliseconds(100))
        #expect(fake.sessions == 0 && fake.commands.isEmpty, "showing the panel and its label pairs with nothing")

        var opened: [UUID?] = []
        let actions = MenuBarActions(live: live, onKeyboard: onKeyboard, windows: router, openWindow: { opened.append($0) }) {}
        actions.turnOnLiveView()
        #expect(await eventually { live.canSend && live.activeLayer == 1 })
        let on = state()
        #expect(on.keyboard == .live && on.layer == 1 && on.canMove && on.usesTiles)
        #expect(on.layers.map(\.title) == ["Main", "Sym+Num", "Brd+Sys"])
        #expect(on.layers.map(\.shortcut) == ["⌃⌥0", "⌃⌥1", "⌃⌥2"])
        #expect(on.layerNote == nil && on.layout != nil)

        actions.moveToLayer(2)
        #expect(await eventually { fake.commands == [.moveToLayer(2)] })
        // Past the layout's layers nothing is sent.
        actions.moveToLayer(3)
        actions.buildAndFlash()
        #expect(opened == [entry.id] && router.pendingBuild?.layout == entry.id)
        live.stopLive()
        #expect(state().keyboard == .liveOff && fake.commands == [.moveToLayer(2)])
        _ = hosts
    }

    @Test func theRefusalShowsWhileTheItemsAreDisabled() async throws {
        let fake = StandInKeyboard(serial: "Q9x2/aa11", events: [])
        let (live, onKeyboard, library) = Self.session(fake)
        #expect(await eventually { live.connection != .noKeyboard })
        live.startLive()
        #expect(await eventually { fake.sessions == 1 })
        let connecting = MenuBarPanelState(live: live, onKeyboard: onKeyboard, shortcuts: nil, library: library, buildTarget: nil)
        #expect(connecting.keyboard == .connecting && !connecting.canMove)
        #expect(connecting.layerNote == "Live View is still connecting to the keyboard.")
        #expect(connecting.running == "Q9x2/aa11" && !connecting.canBuildAndFlash, "an empty library has nothing to build")
    }

    /// A started live session and the layout on its keyboard, over `fake` and an empty in-memory library.
    private static func session(_ fake: StandInKeyboard) -> (LiveSession, OnKeyboard, Library) {
        let live = LiveSession(watcher: fake, link: fake, secureInputProbe: { false })
        let store = MemoryLibrary()
        let library = Library(store: store)
        let onKeyboard = OnKeyboard(library: library, store: store, live: live)
        live.start()
        onKeyboard.start()
        return (live, onKeyboard, library)
    }

    // MARK: Requests

    @Test func requestsOpenTheKeyboardsLayoutAndABuildWaitsForItsWindow() async throws {
        let fake = StandInKeyboard(serial: "KlgM7/40xJ7M")
        let live = LiveSession(watcher: fake, link: fake, secureInputProbe: { false })
        let store = MemoryLibrary()
        let library = Library(store: store)
        let other = await library.create(KeyboardLayout(title: "Other", geometry: "voyager", layers: []))
        let entry = try await library.importOryxJSON(#require(userLayoutData))
        let onKeyboard = OnKeyboard(library: library, store: store, live: live)
        var now = Date(timeIntervalSince1970: 1_000)
        var opened: [UUID?] = []
        let router = WindowRouter(
            library: library, onKeyboard: onKeyboard, live: live, presence: AppPresence(apply: { _ in }), activate: {}, now: { now })
        // No keyboard and no window: the library's first entry (the package store lists the most recently modified
        // first; this in-memory one doesn't sort).
        await library.refresh()
        router.showMainWindow { opened.append($0) }
        #expect(opened == [library.entries.first?.id])

        live.start()
        onKeyboard.start()
        #expect(await eventually { onKeyboard.running?.entry.id == entry.id })
        router.buildAndFlash { opened.append($0) }
        #expect(opened.last == entry.id && router.pendingBuild?.layout == entry.id)
        #expect(other.map { !router.takeBuild(for: $0.id) } ?? false, "another layout's window doesn't take it")
        #expect(router.takeBuild(for: entry.id))
        #expect(!router.takeBuild(for: entry.id), "once")

        // A request no window took in time is dropped, so a later open of that layout doesn't build.
        router.buildAndFlash { opened.append($0) }
        now += WindowRouter.requestLifetime + 1
        #expect(!router.takeBuild(for: entry.id) && router.pendingBuild == nil)
    }

    @Test func anEmptyLibraryOpensTheWelcomeOnlyWithNoWindowOpen() {
        let library = Library(store: MemoryLibrary())
        let presence = AppPresence(apply: { _ in })
        let router = WindowRouter(library: library, onKeyboard: nil, live: nil, presence: presence, activate: {})
        var opened: [UUID?] = []
        router.showMainWindow { opened.append($0) }
        #expect(opened == [nil])
        presence.windowOpened()
        router.showMainWindow { opened.append($0) }
        #expect(opened == [nil], "a window is open: only Sextant comes forward")
        router.buildAndFlash { opened.append($0) }
        #expect(router.pendingBuild == nil)
    }

    /// The user's layout with `count` layers: its own, then copies of Sym+Num.
    static func layout(_ layout: KeyboardLayout, layers count: Int) -> KeyboardLayout {
        var layout = layout
        while layout.layers.count < count {
            layout.layers.append(Layer(title: "Layer \(layout.layers.count)", keys: layout.layers[1].keys))
        }
        layout.layers = Array(layout.layers.prefix(count))
        return layout
    }
}

/// Polls `condition`, letting other tasks run, for up to about two seconds.
@MainActor
private func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    return condition()
}

/// A keyboard plugged in from the start. Each session reports `events` (by default Sym+Num; none, and it stays pairing;
/// an `.ended` ends it) and records the commands it is sent; nothing reaches hardware.
final class StandInKeyboard: DeviceWatcher, KeyboardLink, Sendable {
    private let serial: String
    private let events: [LiveEvent]
    private let state = Mutex<(sessions: Int, commands: [KeyboardCommand])>((0, []))

    init(serial: String, events: [LiveEvent] = [.layer(1)]) {
        self.serial = serial
        self.events = events
    }

    var sessions: Int { state.withLock { $0.sessions } }
    var commands: [KeyboardCommand] { state.withLock { $0.commands } }

    private func record(_ command: KeyboardCommand) { state.withLock { $0.commands.append(command) } }

    func events(for board: BoardDefinition) -> AsyncStream<DeviceEvent> {
        AsyncStream { $0.yield(.attached(.keyboard(KeyboardDevice(id: 1, productID: 0x1977, serial: serial)))) }
    }

    func session(with device: KeyboardDevice, board: BoardDefinition, commands: AsyncStream<KeyboardCommand>) -> AsyncStream<LiveEvent> {
        state.withLock { $0.sessions += 1 }
        let events = events
        return AsyncStream { continuation in
            for event in events {
                continuation.yield(event)
                if case .ended = event { continuation.finish() }
            }
            let task = Task {
                for await command in commands { self.record(command) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Layer shortcuts ⌃⌥0–⌃⌥9, registered nowhere.
@MainActor
final class SilentHotKeys: HotKeys {
    func register(layers: Range<Int>, onPress: @escaping @MainActor (Int) -> Void) {}
    func unregister() {}
    func setPaused(_ paused: Bool) {}
    func shortcut(forLayer layer: Int) -> HotKeyShortcut? {
        HotKeyShortcut(keyCode: 0, modifiers: [.control, .option], text: "⌃⌥\(layer)", keyEquivalent: "\(layer)")
    }
    func conflicts() -> [Int: HotKeyConflict] { [:] }
}
