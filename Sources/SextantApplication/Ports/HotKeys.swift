import Foundation

/// Global shortcuts for moving the keyboard's layer, one per layer (ADR 0048). While registered, the system hands their
/// key presses to Sextant whichever app is frontmost, so nothing else sees them. On the main actor: the system delivers
/// hot-key events on the main thread.
@MainActor
public protocol HotKeys: AnyObject {
    /// Registers the shortcut of each of `layers` system-wide; `onPress` gets the layer whose shortcut was pressed. A
    /// shortcut the user records later is registered in its place, with no further call.
    func register(layers: Range<Int>, onPress: @escaping @MainActor (Int) -> Void)
    /// Unregisters every layer shortcut, so their keys reach other apps again.
    func unregister()
    /// While paused, the registered shortcuts let their keys through to the frontmost app (Sextant's own key recorders)
    /// and stay registered for when it ends.
    func setPaused(_ paused: Bool)
    /// The layer's shortcut, registered or not; nil when the user removed it.
    func shortcut(forLayer layer: Int) -> HotKeyShortcut?
    /// The registered layers whose shortcut can't fire.
    func conflicts() -> [Int: HotKeyConflict]
}

/// Why a registered shortcut can't fire.
public enum HotKeyConflict: Hashable, Sendable {
    /// The system wouldn't register the keys: another app holds them.
    case inUse
    /// A macOS shortcut (System Settings › Keyboard › Keyboard Shortcuts) uses the same keys.
    case takenBySystem
}

/// A key with modifiers, as Settings and menus show it.
public struct HotKeyShortcut: Hashable, Sendable {
    /// The key's virtual key code: which key it is, whatever the keyboard layout prints on it.
    public var keyCode: Int
    public var modifiers: HotKeyModifiers
    /// The whole shortcut in menu symbols: "⌃⌥2".
    public var text: String
    /// What a menu item takes as its key equivalent ("2"); nil for a key a menu can't show.
    public var keyEquivalent: String?

    public init(keyCode: Int, modifiers: HotKeyModifiers, text: String, keyEquivalent: String?) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.text = text
        self.keyEquivalent = keyEquivalent
    }
}

public struct HotKeyModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let control = Self(rawValue: 1 << 0)
    public static let option = Self(rawValue: 1 << 1)
    public static let shift = Self(rawValue: 1 << 2)
    public static let command = Self(rawValue: 1 << 3)
}
