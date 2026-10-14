import AppKit
import Foundation
import SextantApplication
import SextantDomain
import SwiftUI
import Synchronization
import Testing

@testable import SextantUI

/// The App Layers page's model, its lane text and its menu bar row (ADR 0054), over a stand-in keyboard and frontmost
/// app: nothing here watches the real frontmost app or writes to a keyboard.
@MainActor
struct AppLayersPageTests {
    let keyboard = StandInKeyboard(serial: "KlgM7/40xJ7M")
    let apps = StandInApps()
    let live: LiveSession
    let store = MemoryLibrary()
    let library: Library
    let onKeyboard: OnKeyboard
    let switcher: AppLayerSwitcher

    init() {
        live = LiveSession(watcher: keyboard, link: keyboard, secureInputProbe: { false })
        library = Library(store: store)
        onKeyboard = OnKeyboard(library: library, store: store, live: live)
        switcher = AppLayerSwitcher(watcher: apps, onKeyboard: onKeyboard, live: live, store: store)
    }

    /// The user's layout, which the keyboard runs, open in a window.
    func window() async throws -> (LayoutWindowModel, UUID) {
        let entry = try await library.importOryxJSON(#require(userLayoutData))
        live.start()
        onKeyboard.start()
        switcher.start()
        #expect(await eventually { onKeyboard.running != nil })
        let model = LayoutWindowModel(library: library, live: live, onKeyboard: onKeyboard, appLayers: switcher)
        await model.open(entry.id)
        await switcher.load(entry.id)
        return (model, entry.id)
    }

    @Test func addingAnAppMakesARuleOnTheFirstLayerAboveTheBase() async throws {
        let (model, id) = try await window()
        let layout = try #require(model.session?.layout)
        model.appLayers.add(StandInApps.xcode, to: id, layout: layout)
        let rule = try #require(model.appLayers.rules(id).rule(for: StandInApps.xcode.bundleID))
        #expect(rule.layerID == layout.layers[1].id && rule.leaving == .returnToMain && rule.isEnabled)
        #expect(model.appLayers.selection == StandInApps.xcode.bundleID)
        #expect(!model.appLayers.rules(id).isOn, "adding a rule doesn't turn switching on: the switch is the consent")

        model.appLayers.add(StandInApps.xcode, to: id, layout: layout)
        #expect(model.appLayers.rules(id).rules.count == 1, "one rule per app")
        var saved = 0
        for _ in 0..<200 where saved != 1 {
            saved = await store.appLayerRules(of: id).rules.count
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(saved == 1, "saved beside the layout")
        model.appLayers.remove(StandInApps.xcode.bundleID, from: id)
        #expect(model.appLayers.rules(id).rules.isEmpty && model.appLayers.selection == nil)
    }

    @Test func choosingAnAppAddsIt() async throws {
        let (model, id) = try await window()
        let layout = try #require(model.session?.layout)
        await model.appLayers.addApp(at: URL(fileURLWithPath: "/Applications/Xcode.app"), to: id, layout: layout)
        await model.appLayers.addApp(at: URL(fileURLWithPath: "/tmp/not-an-app"), to: id, layout: layout)
        #expect(model.appLayers.rules(id).rules.map(\.name) == ["Xcode"])
        await model.appLayers.refreshRunningApps()
        #expect(model.appLayers.runningApps == [StandInApps.xcode])
    }

    /// The lane's capsule and the menu bar row follow the frontmost app's rule while the keyboard is on its layer.
    @Test func theLaneAndTheMenuBarRowSayWhatHolds() async throws {
        let (model, id) = try await window()
        let layout = try #require(model.session?.layout)
        #expect(MenuBarPanelState.appLayers(switcher, layout: id) == nil, "no rules, no row")
        model.appLayers.add(StandInApps.xcode, to: id, layout: layout)
        #expect(MenuBarPanelState.appLayers(switcher, layout: id) == .init(detail: "Off", isOn: false))
        let actions = MenuBarActions(
            live: live, onKeyboard: onKeyboard,
            windows: WindowRouter(
                library: library, onKeyboard: onKeyboard, live: live, presence: AppPresence(apply: { _ in }), activate: {}),
            openWindow: { _ in }, appLayers: switcher, openSettings: {})
        actions.setAppLayersOn(true)
        #expect(model.appLayers.rules(id).isOn, "the menu bar's switch is the keyboard layout's")
        #expect(MenuBarPanelState.appLayers(switcher, layout: id) == .init(detail: "Paused", isOn: true), "Live View is off")
        #expect(model.appLayers.laneText(id) == nil)

        // Live View on, with the keyboard on Sym+Num (the stand-in's report) while Xcode is in front.
        live.startLive()
        #expect(await eventually { live.canSend && live.activeLayer == 1 })
        apps.bring(StandInApps.xcode)
        #expect(await eventually { switcher.frontmost == StandInApps.xcode })
        #expect(model.appLayers.laneText(id) == "Xcode is frontmost → keyboard on Sym+Num")
        #expect(MenuBarPanelState.appLayers(switcher, layout: id) == .init(detail: "Xcode → Sym+Num", isOn: true))
        #expect(keyboard.commands.isEmpty, "already on Sym+Num, so nothing was sent")
    }

    /// Spec §13.3: the panel stays under 520 pt with the App Layers row and every layer a move can reach.
    @Test func thePanelWithTheAppLayersRowStaysUnder520Points() throws {
        let layout = try KeyboardLayout(oryxJSON: #require(userLayoutData))
        let state = MenuBarPanelState(
            keyboard: .live, running: "Thirty-two layers, revision 3", layout: MenuBarTests.layout(layout, layers: 40), layer: 31,
            shortcuts: Dictionary(uniqueKeysWithValues: (0..<10).map { ($0, "⌃⌥\($0)") }), isSecureInputOn: true,
            buildTarget: "Thirty-two layers", appLayers: .init(detail: "Xcode → Sym+Num", isOn: true))
        let size = NSHostingView(rootView: MenuBarPanelContent(state: state)).fittingSize
        #expect(size.height < 520, "\(size.height) pt")
    }
}

/// The frontmost app as a test sets it: Finder at first.
final class StandInApps: FrontmostAppWatcher, Sendable {
    static let xcode = MacApp(bundleID: "com.apple.dt.Xcode", name: "Xcode")
    private let feed = Mutex<AsyncStream<MacApp>.Continuation?>(nil)

    func activations() -> AsyncStream<MacApp> {
        let (stream, continuation) = AsyncStream.makeStream(of: MacApp.self)
        continuation.yield(MacApp(bundleID: "com.apple.finder", name: "Finder"))
        feed.withLock { $0 = continuation }
        return stream
    }

    func bring(_ app: MacApp) { _ = feed.withLock { $0?.yield(app) } }

    func runningApps() -> [MacApp] { [Self.xcode] }

    func app(at url: URL) -> MacApp? { url.lastPathComponent == "Xcode.app" ? Self.xcode : nil }
}

/// Polls `condition`, letting other tasks run, for up to about two seconds.
@MainActor
private func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    return condition()
}
