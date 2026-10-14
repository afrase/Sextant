import Foundation
import Observation

/// The global layer shortcuts (spec §9.4, ADR 0048): ⌃⌥0–⌃⌥9 until the user remaps them, each moving the keyboard to
/// that layer from any app. Off by default. While on they hold their keys system-wide, and a press that can't move the
/// keyboard (Live View off, no such layer) sends nothing and says why. App-wide.
@MainActor
@Observable
public final class LayerShortcuts {
    /// One shortcut per layer, for layers 0–9.
    public static let layers = 0..<10

    /// Registers the shortcuts when turned on and unregisters them when turned off; the choice is saved.
    public var isOn: Bool {
        didSet {
            guard isOn != oldValue else { return }
            persist(isOn)
            apply()
        }
    }
    /// Each layer's shortcut while on; empty while off.
    public private(set) var shortcuts: [Int: HotKeyShortcut] = [:]
    /// Shortcuts that can't fire while on, by layer.
    public private(set) var conflicts: [Int: HotKeyConflict] = [:]
    /// Why the last press sent nothing; nil once a press sends.
    public private(set) var refusal: LayerMoveRefusal?

    @ObservationIgnored private let hotKeys: any HotKeys
    @ObservationIgnored private let onKeyboard: OnKeyboard
    @ObservationIgnored private let persist: @MainActor (Bool) -> Void
    @ObservationIgnored private let onRefused: @MainActor (LayerMoveRefusal) -> Void
    @ObservationIgnored private var started = false

    /// - Parameters:
    ///   - isOn: the saved choice (Settings › Keyboard); `persist` saves a change.
    ///   - onRefused: tells the user a press sent nothing, whichever app is frontmost.
    public init(
        hotKeys: any HotKeys, onKeyboard: OnKeyboard, isOn: Bool, persist: @escaping @MainActor (Bool) -> Void = { _ in },
        onRefused: @escaping @MainActor (LayerMoveRefusal) -> Void = { _ in }
    ) {
        self.hotKeys = hotKeys
        self.onKeyboard = onKeyboard
        self.isOn = isOn
        self.persist = persist
        self.onRefused = onRefused
    }

    /// Registers the shortcuts if they are on. Call once at launch.
    public func start() {
        guard !started else { return }
        started = true
        apply()
    }

    /// The user recorded or removed a shortcut: the port has registered it already; this rereads it and its conflicts.
    public func shortcutsChanged() {
        guard isOn, started else { return }
        read()
    }

    /// The shortcut a menu item shows for `layer`: only while on, and only one that can fire. A press then reaches only
    /// the hot key, which takes it before the app's menus see it; with the shortcuts off, ⌃⌥ digits do nothing in
    /// Sextant either.
    public func menuShortcut(forLayer layer: Int) -> HotKeyShortcut? {
        conflicts[layer] == nil ? shortcuts[layer] : nil
    }

    /// Why `shortcut` can't be `layer`'s, in words for the recorder; nil when it can.
    public func problem(with shortcut: HotKeyShortcut, forLayer layer: Int) -> String? {
        guard Self.allows(shortcut.modifiers) else {
            return String(
                localized: """
                    Include ⌃ or ⌘. macOS doesn’t take global shortcuts with only ⌥ or ⇧, and without a modifier the key \
                    would move the layer as you type.
                    """)
        }
        let other = Self.layers.first { $0 != layer && hotKeys.shortcut(forLayer: $0) == shortcut }
        return other.map { String(localized: "Layer \($0) already uses \(shortcut.text).") }
    }

    /// A global shortcut needs ⌃ or ⌘: macOS 15 and later refuse ones whose only modifiers are ⌥ or ⌥⇧, and one with
    /// only ⇧, or none, would fire while typing.
    nonisolated public static func allows(_ modifiers: HotKeyModifiers) -> Bool {
        !modifiers.isDisjoint(with: [.control, .command])
    }

    /// A shortcut was pressed.
    func press(_ layer: Int) {
        do {
            try onKeyboard.moveKeyboard(toLayer: layer)
            refusal = nil
        } catch {
            refusal = error
            onRefused(error)
        }
    }

    private func apply() {
        guard started else { return }
        if isOn {
            hotKeys.register(layers: Self.layers) { [weak self] in self?.press($0) }
            read()
        } else {
            hotKeys.unregister()
            (shortcuts, conflicts, refusal) = ([:], [:], nil)
        }
    }

    private func read() {
        let found = Self.layers.compactMap { layer in hotKeys.shortcut(forLayer: layer).map { (layer, $0) } }
        shortcuts = Dictionary(uniqueKeysWithValues: found)
        conflicts = hotKeys.conflicts()
    }
}

/// Why the keyboard's layer can't be moved now (ADR 0048). Menus show it on their disabled items, and a layer shortcut
/// pressed then says it.
public enum LayerMoveRefusal: Error, Hashable, Sendable, LocalizedError {
    case noKeyboard
    case flashMode
    /// Live View is off (ADR 0057): nothing is written to the keyboard.
    case liveOff
    case heldByAnotherApp
    /// Live View is on but hasn't paired with the keyboard yet.
    case connecting
    /// The keyboard runs a layout Sextant doesn't hold, so only layer 0 is known to exist.
    case unknownLayout
    /// The keyboard's layout has no such layer.
    case noSuchLayer(Int)

    init(_ error: DeviceError, layer: Int) {
        self =
            switch error {
            case .notFound: .noKeyboard
            case .heldByAnotherApp: .heldByAnotherApp
            case .hardwareAccessOff: .liveOff
            case .notLive, .io: .connecting
            case .outOfRange: .noSuchLayer(layer)
            }
    }

    public var errorDescription: String? {
        switch self {
        case .noKeyboard: String(localized: "Connect your keyboard to move its layer.")
        case .flashMode: String(localized: "The keyboard is in flash mode.")
        case .liveOff: String(localized: "Turn on Live View to move the keyboard’s layer.")
        case .heldByAnotherApp: DeviceError.heldByAnotherApp.localizedDescription
        case .connecting: String(localized: "Live View is still connecting to the keyboard.")
        case .unknownLayout: String(localized: "Sextant doesn’t have the keyboard’s layout, so it can move it only to layer 0.")
        case let .noSuchLayer(layer): String(localized: "The keyboard’s layout has no layer \(layer).")
        }
    }
}
