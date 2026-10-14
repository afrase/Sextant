// The global layer shortcuts' adapter (ADR 0048): sindresorhus/KeyboardShortcuts registers them with Carbon's
// RegisterEventHotKey (no TCC) and stores each in UserDefaults; its recorder remaps them in Settings › Keyboard. It lives
// in the composition root, so SextantUI never imports the library. Never built by `swift test`: it would take ⌃⌥ digits
// system-wide.

import AppKit
import KeyboardShortcuts
import SextantApplication
import SextantUI
import SwiftUI

@MainActor
final class KeyboardShortcutsHotKeys: HotKeys {
    /// One name per layer, ⌃⌥0–⌃⌥9 until the user records others. A name writes its initial shortcut to UserDefaults
    /// the first time it's made, so they're made only once the shortcuts are on or being recorded; nothing is
    /// registered until `register` adds a handler.
    private lazy var names = zip(LayerShortcuts.layers, KeyboardShortcutsHotKeys.digits).map { layer, digit in
        KeyboardShortcuts.Name("moveKeyboardToLayer\(layer)", initial: .init(digit, modifiers: [.control, .option]))
    }
    private static let digits: [KeyboardShortcuts.Key] = [.zero, .one, .two, .three, .four, .five, .six, .seven, .eight, .nine]
    private var registered: Range<Int>?

    func register(layers: Range<Int>, onPress: @escaping @MainActor (Int) -> Void) {
        unregister()
        registered = layers
        for layer in layers where names.indices.contains(layer) {
            KeyboardShortcuts.onKeyDown(for: names[layer]) { onPress(layer) }
        }
    }

    func unregister() {
        guard let layers = registered else { return }
        for layer in layers where names.indices.contains(layer) { KeyboardShortcuts.removeHandler(for: names[layer]) }
        registered = nil
    }

    func setPaused(_ paused: Bool) {
        // Carbon consumes a registered hot key's press before AppKit sees it; the library's switch unregisters them all
        // with Carbon until it's turned back on.
        KeyboardShortcuts.isEnabled = !paused
    }

    func shortcut(forLayer layer: Int) -> HotKeyShortcut? {
        guard names.indices.contains(layer), let shortcut = names[layer].shortcut else { return nil }
        return HotKeyShortcut(shortcut)
    }

    func conflicts() -> [Int: HotKeyConflict] {
        var found: [Int: HotKeyConflict] = [:]
        for layer in registered ?? 0..<0 where names.indices.contains(layer) {
            guard let shortcut = names[layer].shortcut else { continue }
            // Registration fails when the system won't give Sextant the keys (another app holds them exclusively); a
            // macOS shortcut takes them before Sextant sees them.
            if !KeyboardShortcuts.isEnabled(for: names[layer]) {
                found[layer] = .inUse
            } else if shortcut.isTakenBySystem {
                found[layer] = .takenBySystem
            }
        }
        return found
    }

    /// Settings › Keyboard's recorder for `layer`, refusing what `shortcuts` refuses and rereading after each change.
    func recorder(for shortcuts: LayerShortcuts) -> LayerShortcutRecorder {
        { layer in
            AnyView(
                KeyboardShortcuts.Recorder(for: self.names[layer]) { _ in shortcuts.shortcutsChanged() }
                    .shortcutValidation { shortcut in
                        shortcuts.problem(with: HotKeyShortcut(shortcut), forLayer: layer).map { .disallow(reason: $0) } ?? .allow
                    }
                    .accessibilityLabel(Text("Layer \(layer) shortcut")))
        }
    }
}

extension HotKeyShortcut {
    @MainActor
    fileprivate init(_ shortcut: KeyboardShortcuts.Shortcut) {
        let flags = shortcut.modifiers
        var modifiers: HotKeyModifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        self.init(
            keyCode: shortcut.carbonKeyCode, modifiers: modifiers, text: shortcut.description,
            keyEquivalent: shortcut.nsMenuItemKeyEquivalent)
    }
}
