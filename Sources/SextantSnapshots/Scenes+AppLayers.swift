import AppKit
import Foundation
import SextantApplication
import SextantDomain
import SextantStorage
import SextantUI
import SwiftUI
import Synchronization

// App Layers (spec §8.6, ADR 0054): the page with its rules, Now card and inspector, the empty state, the paused state,
// the lane capsule and the menu bar row. The frontmost app and the keyboard are stand-ins: nothing here watches the real
// frontmost app or writes to a keyboard. The rules are built in code on the user's layout.

extension Scenes {
    static func appLayers(_ f: Fixtures) async -> [SnapshotScene] {
        // A library of its own inside the fixtures' folder (removed with it), so the other scenes' sidebars don't list it.
        guard let fixtures = await f.windowModel().library.location(of: f.entry.id)?.deletingLastPathComponent(),
            let data = try? Data(contentsOf: Fixtures.layoutFile)
        else { return [] }
        let store = PackageLibrary(root: fixtures.appending(path: "app-layers"))
        let library = Library(store: store)
        // The keyboard runs the user's import; "Work Layout", a local copy with no rules, isn't on it.
        guard let entry = try? await library.importOryxJSON(data), var work = try? KeyboardLayout(oryxJSON: data) else { return [] }
        work.title = "Work Layout"
        work.oryx = nil
        guard let empty = await library.create(work) else { return [] }

        // Live View on over a keyboard that moves when told to, running the user's layout.
        let keyboard = MovingKeyboard()
        let live = LiveSession(watcher: keyboard, link: keyboard, followsOnConnect: { false }, secureInputProbe: { false })
        live.start()
        live.startLive()
        let onKeyboard = OnKeyboard(library: library, store: store, live: live)
        onKeyboard.start()
        let apps = SceneApps()
        let switcher = AppLayerSwitcher(watcher: apps, onKeyboard: onKeyboard, live: live, store: store, now: SceneTimes().next)
        switcher.start()
        for _ in 0..<250 where !live.canSend || onKeyboard.running?.entry.id != entry.id {
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard let layout = onKeyboard.running?.layout else { return [] }
        await switcher.load(entry.id)
        switcher.setRules(rules(layout), for: entry.id)
        // Figma moves it to Brd+Sys and stays; Xcode moves it to Sym+Num and back to Main when left; Xcode again.
        let steps: [(MacApp, Int)] = [
            (SceneApps.figma, 1), (SceneApps.safari, 1), (SceneApps.xcode, 2), (SceneApps.safari, 3), (SceneApps.xcode, 4),
        ]
        for (app, switches) in steps {
            apps.bring(app)
            for _ in 0..<100 where switcher.frontmost != app || switcher.history.count != switches {
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        for _ in 0..<100 where live.activeLayer != 1 { try? await Task.sleep(for: .milliseconds(20)) }

        func window(_ id: UUID, _ live: LiveSession, _ onKeyboard: OnKeyboard, _ switcher: AppLayerSwitcher) async -> LayoutWindowModel {
            let model = LayoutWindowModel(library: Library(store: store), live: live, onKeyboard: onKeyboard, appLayers: switcher)
            await model.open(id)
            model.buildFlash = await idleBuildFlash(model)
            model.destination = .appLayers
            // Loads the import the keyboard's serial is matched against, as the window does.
            Task { await model.followKeyboard() }
            try? await Task.sleep(for: .milliseconds(100))
            return model
        }
        var scenes: [SnapshotScene] = []
        let page = await window(entry.id, live, onKeyboard, switcher)
        page.appLayers.selection = SceneApps.xcode.bundleID
        scenes += SnapshotScene.pair("app-layers", size: full) { LayoutWindow(model: page, layoutID: .constant(entry.id)) }
        scenes.append(
            SnapshotScene("app-layers-min-light", size: CGSize(width: 1120, height: 640)) {
                LayoutWindow(model: page, layoutID: .constant(entry.id))
            })
        let blank = await window(empty.id, live, onKeyboard, switcher)
        scenes += SnapshotScene.pair("app-layers-empty", size: full) { LayoutWindow(model: blank, layoutID: .constant(empty.id)) }

        // The board while Xcode's rule holds: the lane's capsule, Follow off.
        let board = await window(entry.id, live, onKeyboard, switcher)
        board.destination = .layer(1)
        scenes.append(SnapshotScene("app-layers-lane-light", size: full) { LayoutWindow(model: board, layoutID: .constant(entry.id)) })
        // Beside the Lighting lens's tools in the narrowest window: the rule keeps its layer's name.
        let painting = await window(entry.id, live, onKeyboard, switcher)
        painting.destination = .layer(1)
        painting.lens = .lighting
        scenes.append(
            SnapshotScene("app-layers-lane-lighting-min-light", size: CGSize(width: 1120, height: 640)) {
                LayoutWindow(model: painting, layoutID: .constant(entry.id))
            })

        // The same rules with the keyboard plugged in and Live View off.
        let plugged = PluggedInKeyboard(serial: "KlgM7/40xJ7M")
        let liveOff = LiveSession(watcher: plugged, link: plugged, secureInputProbe: { false })
        liveOff.start()
        let offKeyboard = OnKeyboard(library: library, store: store, live: liveOff)
        offKeyboard.start()
        let offSwitcher = AppLayerSwitcher(watcher: SceneApps(), onKeyboard: offKeyboard, live: liveOff, store: store)
        await offSwitcher.load(entry.id)
        for _ in 0..<100 where offKeyboard.running == nil { try? await Task.sleep(for: .milliseconds(20)) }
        let paused = await window(entry.id, liveOff, offKeyboard, offSwitcher)
        scenes += SnapshotScene.pair("app-layers-paused", size: full) { LayoutWindow(model: paused, layoutID: .constant(entry.id)) }

        scenes += menuBarPanels(layout)
        return scenes + (await troubles(root: fixtures.appending(path: "app-layers-troubles"), data: data, live: live))
    }

    /// The menu bar panel's App Layers row: with tiles, with rows (one fewer under the row), and with the Heatmap's typing
    /// line too.
    private static func menuBarPanels(_ layout: KeyboardLayout) -> [SnapshotScene] {
        // With tiles.
        let state = MenuBarPanelState(
            keyboard: .live, running: "\(layout.title), revision 1", layout: layout, layer: 1, buildTarget: layout.title,
            appLayers: MenuBarPanelState.AppLayers(detail: "Xcode → Sym+Num", isOn: true))
        let size = NSHostingView(rootView: MenuBarPanelContent(state: state)).fittingSize
        var scenes = SnapshotScene.pair("menubar-panel-app-layers", size: size, chrome: .content) { MenuBarPanelContent(state: state) }
        // With rows, which show one fewer under the row; paused, as while Live View pairs again.
        let twelve = twelveLayers(layout)
        let list = MenuBarPanelState(
            keyboard: .live, running: "Twelve layers, revision 4", layout: twelve, layer: 5,
            shortcuts: Dictionary(uniqueKeysWithValues: (0..<10).map { ($0, "⌃⌥\($0)") }), buildTarget: twelve.title,
            appLayers: MenuBarPanelState.AppLayers(detail: "Paused", isOn: true))
        let listSize = NSHostingView(rootView: MenuBarPanelContent(state: list)).fittingSize
        scenes.append(
            SnapshotScene("menubar-panel-app-layers-list-light", size: listSize, chrome: .content) { MenuBarPanelContent(state: list) })
        // And with heatmap recording's typing line, one row fewer again; during secure input, which the line then says
        // for the mini map too. The tallest the panel gets.
        let secure = MenuBarPanelState(
            keyboard: .live, running: "Twelve layers, revision 4", layout: twelve, layer: 5,
            shortcuts: Dictionary(uniqueKeysWithValues: (0..<10).map { ($0, "⌃⌥\($0)") }), isSecureInputOn: true,
            buildTarget: twelve.title, appLayers: MenuBarPanelState.AppLayers(detail: "Xcode → Sym+Num", isOn: true))
        let typing = TypingStats(today: 12_408, wordsPerMinute: 0, pause: "Paused while you type in a password field")
        let typingSize = NSHostingView(rootView: MenuBarPanelContent(state: secure, typingStats: typing)).fittingSize
        scenes += SnapshotScene.pair("menubar-panel-app-layers-typing", size: typingSize, chrome: .content) {
            MenuBarPanelContent(state: secure, typingStats: typing)
        }
        return scenes
    }

    /// The page when a rule change didn't save, then when a rule's layer was deleted from the working copy though the
    /// keyboard still has it. A library of their own: they break its `app-layers.json` and change its working copy.
    private static func troubles(root: URL, data: Data, live: LiveSession) async -> [SnapshotScene] {
        let store = PackageLibrary(root: root)
        let library = Library(store: store)
        guard let entry = try? await library.importOryxJSON(data), let file = await store.location(of: entry.id) else { return [] }
        let onKeyboard = OnKeyboard(library: library, store: store, live: live)
        onKeyboard.start()
        for _ in 0..<100 where onKeyboard.running?.entry.id != entry.id { try? await Task.sleep(for: .milliseconds(20)) }
        guard let layout = onKeyboard.running?.layout else { return [] }
        func window(_ switcher: AppLayerSwitcher) async -> LayoutWindowModel {
            await switcher.load(entry.id)
            let model = LayoutWindowModel(library: Library(store: store), live: live, onKeyboard: onKeyboard, appLayers: switcher)
            await model.open(entry.id)
            model.buildFlash = await idleBuildFlash(model)
            model.destination = .appLayers
            Task { await model.followKeyboard() }
            try? await Task.sleep(for: .milliseconds(100))
            return model
        }
        let saved = AppLayerSwitcher(watcher: SceneApps(), onKeyboard: onKeyboard, live: live, store: store)
        await saved.load(entry.id)
        saved.setRules(rules(layout), for: entry.id)
        for _ in 0..<100 where (try? await store.appLayerRules(of: entry.id)) != rules(layout) {
            try? await Task.sleep(for: .milliseconds(20))
        }

        // A folder where the file goes: the switch turned off can't be saved.
        let unsaved = AppLayerSwitcher(watcher: SceneApps(), onKeyboard: onKeyboard, live: live, store: store)
        await unsaved.load(entry.id)
        let rulesFile = file.appending(path: "app-layers.json")
        try? FileManager.default.removeItem(at: rulesFile)
        try? FileManager.default.createDirectory(at: rulesFile, withIntermediateDirectories: false)
        var off = unsaved.rules(for: entry.id)
        off.isOn = false
        unsaved.setRules(off, for: entry.id)
        for _ in 0..<100 where unsaved.saveError(for: entry.id) == nil { try? await Task.sleep(for: .milliseconds(20)) }
        let model = await window(unsaved)
        var scenes = SnapshotScene.pair("app-layers-unsaved", size: full) { LayoutWindow(model: model, layoutID: .constant(entry.id)) }

        // Brd+Sys deleted here but not flashed: Figma's rule still moves the keyboard there.
        let deleted = await window(saved)
        deleted.session?.deleteLayer(2)
        deleted.appLayers.selection = SceneApps.figma.bundleID
        scenes += SnapshotScene.pair("app-layers-deleted", size: full) { LayoutWindow(model: deleted, layoutID: .constant(entry.id)) }
        return scenes
    }

    /// Xcode on Sym+Num and back to Main when left, Figma on Brd+Sys staying there, Mail on Sym+Num, and Terminal off.
    private static func rules(_ layout: KeyboardLayout) -> AppLayerRules {
        AppLayerRules(
            isOn: true,
            rules: [
                AppLayerRule(bundleID: SceneApps.xcode.bundleID, name: "Xcode", layerID: layout.layers[1].id),
                AppLayerRule(bundleID: SceneApps.figma.bundleID, name: "Figma", layerID: layout.layers[2].id, leaving: .stay),
                AppLayerRule(bundleID: "com.apple.mail", name: "Mail", layerID: layout.layers[1].id, leaving: .stay),
                AppLayerRule(bundleID: "com.apple.Terminal", name: "Terminal", layerID: layout.layers[2].id, isEnabled: false),
            ])
    }
}

/// The frontmost app as a scene sets it: Finder at first.
private final class SceneApps: FrontmostAppWatcher {
    static let finder = MacApp(bundleID: "com.apple.finder", name: "Finder")
    static let xcode = MacApp(bundleID: "com.apple.dt.Xcode", name: "Xcode")
    static let safari = MacApp(bundleID: "com.apple.Safari", name: "Safari")
    static let figma = MacApp(bundleID: "com.figma.Desktop", name: "Figma")

    private let feed = Mutex<AsyncStream<MacApp>.Continuation?>(nil)

    func activations() -> AsyncStream<MacApp> {
        let (stream, continuation) = AsyncStream.makeStream(of: MacApp.self)
        continuation.yield(Self.finder)
        feed.withLock { $0 = continuation }
        return stream
    }

    func bring(_ app: MacApp) { _ = feed.withLock { $0?.yield(app) } }

    func runningApps() -> AsyncStream<[MacApp]> { AsyncStream { $0.yield([Self.finder, Self.safari, Self.xcode]) } }

    func app(at url: URL) -> MacApp? { nil }
}

/// A keyboard plugged in from the start whose session reports layer 0, then each layer it is moved to, as the firmware
/// does. Its commands go nowhere else.
private struct MovingKeyboard: DeviceWatcher, KeyboardLink {
    func events(for board: BoardDefinition) -> AsyncStream<DeviceEvent> {
        AsyncStream { $0.yield(.attached(.keyboard(KeyboardDevice(id: 1, productID: 0x1977, serial: "KlgM7/40xJ7M")))) }
    }

    func session(with device: KeyboardDevice, board: BoardDefinition, commands: AsyncStream<KeyboardCommand>) -> AsyncStream<LiveEvent> {
        AsyncStream { continuation in
            continuation.yield(.layer(0))
            let task = Task {
                for await command in commands { if case let .moveToLayer(layer) = command { continuation.yield(.layer(layer)) } }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Switch times a minute apart from 9:41, so the inspector's times read the same in every render.
private final class SceneTimes: Sendable {
    private let minutes = Mutex(0)

    func next() -> Date {
        let minute = minutes.withLock { minute in
            defer { minute += 1 }
            return minute
        }
        return Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 9, minute: 41 + minute)) ?? Date()
    }
}
