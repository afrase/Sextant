import Clocks
import Foundation
import SextantDomain
import Testing

@testable import SextantApplication

/// The global layer shortcuts and Move Keyboard to Layer (ADR 0048), on FakeHotKeys and FakeKeyboardLink: nothing here
/// registers a real hot key or writes to a keyboard.
@MainActor
struct LayerShortcutsTests {
    let store = InMemoryLibrary()
    let watcher = FakeDeviceWatcher()
    let link = FakeKeyboardLink()
    let clock = TestClock()
    let hotKeys = FakeHotKeys()
    let live: LiveSession
    let library: Library
    let onKeyboard: OnKeyboard

    init() {
        live = LiveSession(watcher: watcher, link: link, clock: clock) { false }
        library = Library(store: store)
        onKeyboard = OnKeyboard(library: library, store: store, live: live)
    }

    func shortcuts(on: Bool, saved: @escaping @MainActor (Bool) -> Void = { _ in }) -> LayerShortcuts {
        let shortcuts = LayerShortcuts(hotKeys: hotKeys, onKeyboard: onKeyboard, isOn: on, persist: saved)
        shortcuts.start()
        return shortcuts
    }

    /// The user's layout (Main, Sym+Num, Brd+Sys) on a plugged-in keyboard that Sextant knows it runs.
    func knownKeyboard(serial: String = "KlgM7/40xJ7M") async throws {
        _ = try await library.importOryxJSON(Fixtures.userLayoutData)
        live.start()
        onKeyboard.start()
        watcher.attach(.keyboard(.voyager(serial: serial)))
        #expect(await eventually { live.firmwareSerial == serial })
    }

    /// Turns Live View on and pairs its session, which reports `layer`.
    func goLive(layer: Int = 0) async -> Bool {
        live.startLive()
        guard await eventually({ link.sessionCount == 1 }) else { return false }
        link.send(.layer(layer))
        return await eventually {
            await clock.advance(by: .milliseconds(17))
            return live.canSend
        }
    }

    // MARK: Registering

    @Test func offRegistersNothingAndOnRegistersTen() {
        var saved: [Bool] = []
        let shortcuts = shortcuts(on: false) { saved.append($0) }
        #expect(hotKeys.registered == nil && shortcuts.shortcuts.isEmpty)

        shortcuts.isOn = true
        #expect(hotKeys.registered == 0..<10)
        #expect(shortcuts.shortcuts[2]?.text == "⌃⌥2" && shortcuts.shortcuts.count == 10)

        shortcuts.isOn = false
        #expect(hotKeys.registered == nil && shortcuts.shortcuts.isEmpty)
        #expect(saved == [true, false], "each change is saved")
    }

    @Test func onAtLaunchRegistersOnlyOnceStarted() {
        let shortcuts = LayerShortcuts(hotKeys: hotKeys, onKeyboard: onKeyboard, isOn: true)
        #expect(hotKeys.registered == nil)
        shortcuts.start()
        #expect(hotKeys.registered == 0..<10)
    }

    @Test func reportsConflictsAndLeavesThemOffMenus() {
        hotKeys.conflicting = [3: .inUse, 5: .takenBySystem]
        let shortcuts = shortcuts(on: true)
        #expect(shortcuts.conflicts == [3: .inUse, 5: .takenBySystem])
        #expect(shortcuts.menuShortcut(forLayer: 3) == nil, "a menu can't promise a shortcut that won't fire")
        #expect(shortcuts.menuShortcut(forLayer: 4)?.text == "⌃⌥4")

        hotKeys.conflicting = [:]
        hotKeys.stored[3] = .ctrlOpt(keyCode: 0x20, "U")
        shortcuts.shortcutsChanged()
        #expect(shortcuts.conflicts.isEmpty && shortcuts.menuShortcut(forLayer: 3)?.text == "⌃⌥U", "rerecorded")
    }

    @Test func menusShowNoShortcutWhileOff() {
        let shortcuts = shortcuts(on: false)
        #expect(LayerShortcuts.layers.allSatisfy { shortcuts.menuShortcut(forLayer: $0) == nil })
    }

    @Test func refusesOnlyOptionOrShiftAndDuplicates() {
        let shortcuts = shortcuts(on: true)
        let modifiers: [(HotKeyModifiers, Bool)] = [
            ([.control, .option], true), ([.command], true), ([.control], true), ([.option], false), ([.option, .shift], false),
            ([.shift], false), ([], false),
        ]
        for (set, allowed) in modifiers {
            #expect(LayerShortcuts.allows(set) == allowed, "\(set.rawValue)")
            let shortcut = HotKeyShortcut(keyCode: 0x11, modifiers: set, text: "T", keyEquivalent: "t")
            #expect((shortcuts.problem(with: shortcut, forLayer: 1) == nil) == allowed)
        }
        let taken = HotKeyShortcut.ctrlOpt(keyCode: 0x13, "2")
        #expect(shortcuts.problem(with: taken, forLayer: 1) == "Layer 2 already uses ⌃⌥2.")
        #expect(shortcuts.problem(with: taken, forLayer: 2) == nil, "its own shortcut")
    }

    // MARK: Pressing

    @Test func pressingTwoSendsOneMoveToLayerTwo() async throws {
        let shortcuts = shortcuts(on: true)
        try await knownKeyboard()
        #expect(await eventually { onKeyboard.running != nil })
        #expect(await goLive())
        hotKeys.press(2)
        #expect(await eventually { link.commands == [[.moveToLayer(2)]] })
        #expect(shortcuts.refusal == nil)
    }

    @Test func sevenOnAThreeLayerLayoutSendsNothing() async throws {
        var told: [LayerMoveRefusal] = []
        let shortcuts = LayerShortcuts(hotKeys: hotKeys, onKeyboard: onKeyboard, isOn: true) { _ in
        } onRefused: {
            told.append($0)
        }
        shortcuts.start()
        try await knownKeyboard()
        #expect(await eventually { onKeyboard.running?.layout.layers.count == 3 })
        #expect(await goLive())
        hotKeys.press(7)
        hotKeys.press(1)
        #expect(await eventually { link.commands == [[.moveToLayer(1)]] }, "only layer 1 is sent")
        #expect(told == [.noSuchLayer(7)])
        #expect(shortcuts.refusal == nil, "the later press sent")
    }

    @Test func liveViewOffSendsNothingAndSaysWhy() async throws {
        var told: [LayerMoveRefusal] = []
        let shortcuts = LayerShortcuts(hotKeys: hotKeys, onKeyboard: onKeyboard, isOn: true) { _ in
        } onRefused: {
            told.append($0)
        }
        shortcuts.start()
        try await knownKeyboard()
        #expect(await eventually { onKeyboard.running != nil })
        hotKeys.press(1)
        #expect(shortcuts.refusal == .liveOff && told == [.liveOff])
        #expect(shortcuts.refusal?.localizedDescription == "Turn on Live View to move the keyboard’s layer.")
        #expect(link.sessionCount == 0, "nothing paired, nothing written")
    }

    @Test func anUnknownLayoutMovesOnlyToLayerZero() async throws {
        live.start()
        onKeyboard.start()
        watcher.attach(.keyboard(.voyager(serial: "Q9x2/aa11")))
        #expect(await goLive())
        #expect(throws: LayerMoveRefusal.unknownLayout) { try onKeyboard.moveKeyboard(toLayer: 1) }
        try onKeyboard.moveKeyboard(toLayer: 0)
        #expect(await eventually { link.commands == [[.moveToLayer(0)]] })
    }

    // MARK: Menu enablement

    /// Keyboard ▸ Move Keyboard to Layer and the Device popover ask with a dry run, which never sends.
    @Test func menuItemsAreEnabledOnlyOverAPairedSession() async throws {
        func refusal(_ layer: Int = 1) -> LayerMoveRefusal? {
            do {
                try onKeyboard.moveKeyboard(toLayer: layer, dryRun: true)
                return nil
            } catch { return error }
        }
        live.start()
        onKeyboard.start()
        #expect(refusal() == .noKeyboard)
        try await knownKeyboard()
        #expect(await eventually { onKeyboard.running != nil })
        #expect(refusal() == .liveOff)
        live.startLive()
        #expect(await eventually { link.sessionCount == 1 })
        #expect(refusal() == .connecting, "Live View on, not paired yet")
        link.send(.layer(0))
        #expect(
            await eventually {
                await clock.advance(by: .milliseconds(17)); return live.canSend
            })
        #expect(refusal() == nil && refusal(3) == .noSuchLayer(3))
        #expect(link.commands == [[]], "a dry run sends nothing")
        live.stopLive()
        #expect(refusal() == .liveOff)
        watcher.detach(1)
        watcher.attach(.bootloader(.stm32()))
        #expect(await eventually { refusal() == .flashMode })
    }
}

/// Hot keys that never reach the system: the test presses them.
@MainActor
final class FakeHotKeys: HotKeys {
    /// The registered layers; nil while unregistered.
    private(set) var registered: Range<Int>?
    private var onPress: (@MainActor (Int) -> Void)?
    /// ⌃⌥0–⌃⌥9, the defaults.
    var stored: [Int: HotKeyShortcut] = Dictionary(
        uniqueKeysWithValues: [0x1D, 0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19].enumerated().map { layer, code in
            (layer, HotKeyShortcut.ctrlOpt(keyCode: code, "\(layer)"))
        })
    var conflicting: [Int: HotKeyConflict] = [:]

    func register(layers: Range<Int>, onPress: @escaping @MainActor (Int) -> Void) {
        registered = layers
        self.onPress = onPress
    }

    func unregister() {
        registered = nil
        onPress = nil
    }

    func shortcut(forLayer layer: Int) -> HotKeyShortcut? { stored[layer] }

    func conflicts() -> [Int: HotKeyConflict] { registered == nil ? [:] : conflicting }

    /// The user presses layer `layer`'s shortcut; nothing happens unless it's registered.
    func press(_ layer: Int) {
        guard registered?.contains(layer) == true else { return }
        onPress?(layer)
    }
}

extension HotKeyShortcut {
    static func ctrlOpt(keyCode: Int, _ key: String) -> Self {
        Self(keyCode: keyCode, modifiers: [.control, .option], text: "⌃⌥" + key, keyEquivalent: key.lowercased())
    }
}
