import Foundation
import SextantApplication
import SextantDomain

/// What the menu bar panel shows (spec §8.3), read from the live session, the layout on the keyboard and the layer
/// shortcuts. A value, so the panel can be drawn and tested without a keyboard.
public struct MenuBarPanelState: Equatable {
    public enum Keyboard: Equatable, Sendable {
        case none, flashMode, liveOff, heldByAnotherApp
        /// Live View is on and no session is paired: it hasn't paired yet, or is pairing again after one ended.
        case connecting
        /// A paired session: choosing a layer sends.
        case live
    }

    /// One tile or row of "Layer on the keyboard".
    struct LayerItem: Equatable, Identifiable {
        var index: Int
        var title: String
        var color: HexColor?
        /// The global shortcut's text ("⌃⌥3"), while the shortcuts are on and it can fire.
        var shortcut: String?

        var id: Int { index }
    }

    /// A Build & Flash under way in a window: waiting for flash mode, or writing (`progress`, 0–1).
    public struct Flash: Equatable, Sendable {
        var title: String
        var progress: Double?

        public init(title: String, progress: Double?) {
            self.title = title
            self.progress = progress
        }
    }

    /// App Layers for the keyboard's layout (spec §8.3): what its rules do now, and their switch.
    public struct AppLayers: Equatable, Sendable {
        /// "Xcode → Sym+Num", "On", "Paused" or "Off".
        var detail: String
        var isOn: Bool
        /// False while the last change to these rules hasn't saved: the next launch would read the ones from before.
        var isSaved: Bool

        public init(detail: String, isOn: Bool, isSaved: Bool = true) {
            self.detail = detail
            self.isOn = isOn
            self.isSaved = isSaved
        }
    }

    /// Tiles up to this many layers, rows with their shortcuts beyond (spec §8.3).
    static let maxTiles = 4

    var boardName: String
    var keyboard: Keyboard
    /// "My MacOS Layout, revision 3": what the keyboard runs, as it was flashed (ADR 0039); its serial when Sextant
    /// doesn't have that layout.
    var running: String?
    /// The keyboard's layout, for the mini map; nil when Sextant doesn't have it.
    var layout: KeyboardLayout?
    var layer: Int?
    /// The layers the keyboard can be moved to: its layout's, or only layer 0 when Sextant doesn't have it.
    var layers: [LayerItem] = []
    /// How the layer's key reaches it ("held by Space (key 51)").
    var activator: String?
    /// Why choosing a layer sends nothing (the items are disabled), or why only layer 0 is offered; nil otherwise.
    var layerNote: String?
    var canMove = false
    var pressed: Set<Int> = []
    var isSecureInputOn = false
    var flash: Flash?
    /// The layout Build & Flash… builds and writes, named on the row so the click consents to that layout (ADR 0056);
    /// nil with an empty library.
    var buildTarget: String?
    /// Shown while the keyboard runs a library layout that has App Layers rules.
    var appLayers: AppLayers?

    /// A panel from given values, for snapshots. Layers come from `layout`, or only layer 0 without one, while the
    /// keyboard is live or connecting; `shortcuts` gives each one's global shortcut.
    public init(
        keyboard: Keyboard, boardName: String = BoardDefinition.voyager.displayName, running: String? = nil,
        layout: KeyboardLayout? = nil, layer: Int? = nil, shortcuts: [Int: String] = [:], layerNote: String? = nil,
        canMove: Bool = true, pressed: Set<Int> = [], isSecureInputOn: Bool = false, flash: Flash? = nil,
        buildTarget: String? = nil, appLayers: AppLayers? = nil
    ) {
        self.boardName = boardName
        self.keyboard = keyboard
        self.running = running
        self.layout = layout
        self.layer = layer
        self.layerNote = layerNote
        self.canMove = canMove
        self.pressed = pressed
        self.isSecureInputOn = isSecureInputOn
        self.flash = flash
        self.buildTarget = buildTarget
        self.appLayers = appLayers
        if keyboard == .live || keyboard == .connecting { layers = Self.items(layout) { shortcuts[$0] } }
        if let layout, let layer, layer > 0 { activator = KeyText.activator(layout: layout, layer: layer)?.text }
    }

    /// The layers Move Keyboard to Layer offers, with their shortcuts.
    static func items(_ layout: KeyboardLayout?, shortcut: (Int) -> String?) -> [LayerItem] {
        MoveKeyboardToLayerMenu.reachableLayers(layout).map {
            LayerItem(index: $0.index, title: $0.title, color: $0.color, shortcut: shortcut($0.index))
        }
    }

    var usesTiles: Bool { layers.count <= Self.maxTiles }

    var canBuildAndFlash: Bool { buildTarget != nil }

    /// After "Layer on the keyboard": how the layer is reached, or, when the keyboard is on a layer the panel doesn't
    /// list (a layout Sextant doesn't have), that layer's number.
    var layerDetail: String? {
        guard let layer, !layers.contains(where: { $0.index == layer }) else { return activator }
        return String(localized: "On layer \(layer)")
    }

    /// The status line under the board's name.
    var status: String {
        switch keyboard {
        case .none: String(localized: "Not connected")
        case .flashMode: String(localized: "In flash mode")
        case .liveOff: String(localized: "Connected · Live View off")
        case .heldByAnotherApp: String(localized: "Connected · in use by Keymapp")
        case .connecting: String(localized: "Connected · connecting…")
        case .live: String(localized: "Connected · Live View on")
        }
    }
}

extension MenuBarPanelState {
    /// The panel for the keyboard as it is now.
    /// - Parameters:
    ///   - buildTarget: the layout Build & Flash… acts on (``WindowRouter/target``).
    ///   - switcher: App Layers, whose row shows for the keyboard's layout.
    @MainActor
    init(
        live: LiveSession, onKeyboard: OnKeyboard, shortcuts: LayerShortcuts?, library: Library, buildTarget: UUID?,
        appLayers switcher: AppLayerSwitcher? = nil, board: BoardDefinition = .voyager
    ) {
        boardName = board.displayName
        switch live.connection {
        case .noKeyboard: keyboard = .none
        case .bootloader: keyboard = .flashMode
        case .liveOff: keyboard = .liveOff
        case .heldByAnotherApp: keyboard = .heldByAnotherApp
        // Paired or not, as Move Keyboard to Layer decides: the last session's layer stays in `activeLayer` while the
        // next one pairs, and a session can pair on key events before it reports a layer.
        case .connected: keyboard = live.canSend ? .live : .connecting
        }
        let running = onKeyboard.running
        if let running {
            self.running =
                running.revision.map { String(localized: "\(running.entry.title), revision \($0.number)") } ?? running.entry.title
        } else if keyboard != .none, keyboard != .flashMode {
            self.running = live.firmwareSerial
        }
        layout = running?.layout
        layer = keyboard == .live ? live.activeLayer : nil
        pressed = live.pressedKeys
        isSecureInputOn = live.isSecureInputOn
        if let id = live.flashingLayoutID {
            flash = Flash(title: library.entries.first { $0.id == id }?.title ?? "", progress: live.flashProgress)
        }
        self.buildTarget = buildTarget.flatMap { id in library.entries.first { $0.id == id }?.title }
        if let switcher, let id = running?.entry.id { appLayers = Self.appLayers(switcher, layout: id) }
        guard keyboard == .live || keyboard == .connecting else { return }
        layers = Self.items(layout) { shortcuts?.menuShortcut(forLayer: $0)?.text }
        let heading = MoveKeyboardToLayerMenu.heading(onKeyboard)
        layerNote = heading?.text
        canMove = heading?.enabled ?? true
        if let layout, let layer, layer > 0 { activator = KeyText.activator(layout: layout, layer: layer)?.text }
    }
}

extension MenuBarPanelState {
    /// The keyboard layout's App Layers row; nil when that layout has no rules.
    @MainActor
    static func appLayers(_ switcher: AppLayerSwitcher, layout id: UUID) -> AppLayers? {
        let rules = switcher.rules(for: id)
        guard !rules.rules.isEmpty else { return nil }
        let detail =
            switch switcher.state(for: id) {
            case .off: String(localized: "Off")
            case .paused: String(localized: "Paused")
            case .on: switcher.applied(for: id).map { "\($0.app) → \($0.layerName)" } ?? String(localized: "On")
            }
        return AppLayers(detail: detail, isOn: rules.isOn, isSaved: switcher.saveError(for: id) == nil)
    }
}
