import Foundation

/// Mock data for every surface. Everything here is deterministic (no randomness at runtime, no I/O
/// besides reading PrototypeKit's own bundle), so snapshots are stable.
public enum Samples {
    /// The user's real layout "My MacOS Layout [fork]" (KlgM7 / 40xJ7M): Main, Sym+Num (#00F0FF), Brd+Sys (#42FF00).
    /// The Navigator trackpad (right half) is filled in from the user's full revision when the file lacks it.
    public static let layout: KeyboardLayout = {
        do {
            var l = try KeyboardLayout(oryxFile: PrototypeResources.userLayoutURL)
            if l.createdAt == nil {
                // From the user's full revision record (my-layout-KlgM7-full.json): 2026-09-16 05:05:39 UTC.
                l.createdAt = Date(timeIntervalSince1970: 1_789_535_139)
            }
            if l.navigator == nil {
                l.navigator = NavigatorConfig(kind: .trackpad, side: .right, options: [
                    "tap": .bool(true), "tapRight": .bool(true), "scrollInertia": .bool(true), "scrollWithTwoFingers": .bool(true),
                ])
            }
            return l
        } catch {
            fatalError("PrototypeKit: bundled layout failed to decode: \(error)")
        }
    }()

    /// Voyager geometry (same as ``BoardGeometry/voyager``).
    public static var geometry: BoardGeometry { .voyager }

    /// The firmware settings catalog (14 sections, 100 settings).
    public static var settingsCatalog: SettingsCatalog { .voyager }

    /// Example non-default settings for designing "modified" states. The user's real config is empty
    /// (only `qmkCanary`), so these are illustrative, typical home-row-mod tweaks.
    public static let settingsOverrides: [String: SettingValue] = [
        "tappingTerm": .number(180),
        "flowTap": .number(120),
        "chordalHold": .bool(true),
        "chordalHoldExcludeThumbs": .bool(true),
        "permissiveHold": .bool(true),
        "comboTerm": .number(40),
        "rgbTimeout": .number(5),
        "capsLockStatus": .bool(true),
        "disabledAnimations": .strings(["rainbowPinwheels", "pixelFractal", "digitalRain", "riverflow"]),
    ]

    // MARK: Combos & macros

    /// Combos for the combo editor: J+K → Esc, D+F → Tab (layout-wide).
    public static let combos: [Combo] = [
        Combo(id: "combo-jk", name: "J + K → Escape", keyIndices: [39, 40], output: .code("KC_ESCAPE")),
        Combo(id: "combo-df", name: "D + F → Tab", keyIndices: [15, 16], output: .code("KC_TAB")),
    ]

    /// The user's layout with ``combos`` added (for combo surfaces).
    public static var layoutWithCombos: KeyboardLayout {
        var l = layout
        l.combos = combos
        return l
    }

    /// Example macros with steps and delays. The first is ``macro``.
    public static let macros: [Macro] = [
        Macro(name: "Open Keymap", steps: [
            MacroStep(code: "KC_O", modifiers: [.leftCommand, .leftShift], delay: 150),
            MacroStep(code: "KC_K"), MacroStep(code: "KC_E"), MacroStep(code: "KC_Y"),
            MacroStep(code: "KC_M"), MacroStep(code: "KC_A"), MacroStep(code: "KC_P", delay: 60),
            MacroStep(code: "KC_ENTER"),
        ]),
        Macro(name: "Sign-off", steps: [
            MacroStep(code: "KC_T", modifiers: [.leftShift]), MacroStep(code: "KC_H"), MacroStep(code: "KC_A"),
            MacroStep(code: "KC_N"), MacroStep(code: "KC_K"), MacroStep(code: "KC_S"), MacroStep(code: "KC_COMMA", delay: 30),
            MacroStep(code: "KC_ENTER", delay: 30), MacroStep(code: "KC_A", modifiers: [.leftShift]), MacroStep(code: "KC_A"),
            MacroStep(code: "KC_R"), MacroStep(code: "KC_O"), MacroStep(code: "KC_N"),
        ]),
    ]

    /// "Open Keymap": ⌘⇧O, wait 150 ms, type "keymap", wait 60 ms, Return.
    public static var macro: Macro { macros[0] }

    // MARK: App-aware layers

    /// Rules mapping the frontmost app to a layer.
    public static let appRules: [AppLayerRule] = [
        AppLayerRule(id: "xcode", appName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode", layer: 1, symbolName: "hammer"),
        AppLayerRule(id: "figma", appName: "Figma", bundleIdentifier: "com.figma.Desktop", layer: 2, symbolName: "pencil.and.ruler"),
        AppLayerRule(id: "terminal", appName: "Terminal", bundleIdentifier: "com.apple.Terminal", layer: 1, symbolName: "terminal"),
        AppLayerRule(id: "music", appName: "Music", bundleIdentifier: "com.apple.Music", layer: 2, symbolName: "music.note"),
        AppLayerRule(id: "safari", appName: "Safari", bundleIdentifier: "com.apple.Safari", layer: 0, isEnabled: false, symbolName: "safari"),
    ]

    /// The app the mock treats as frontmost.
    public static let frontmostAppBundleIdentifier = "com.apple.dt.Xcode"

    /// Layer chosen by ``appRules`` for ``frontmostAppBundleIdentifier``.
    public static var appRuleActiveLayer: Int? {
        appRules.first { $0.isEnabled && $0.bundleIdentifier == frontmostAppBundleIdentifier }?.layer
    }

    // MARK: Other surfaces

    /// Seven days of key usage (see ``KeyHeatmap``).
    public static let heatmap: KeyHeatmap = .sample(layout: layout)

    /// Four revisions with per-key diffs (see ``RevisionHistory``).
    public static let history: RevisionHistory = .sample(current: layout)

    /// Oryx import preview for https://configure.zsa.io/voyager/layouts/KlgM7/40xJ7M/0.
    public static let oryxImport: OryxImportPreview = .sample(layout: layout)

    /// The sample build failure (an unknown keycode on Brd+Sys key 45), mapped to a key.
    public static var buildFailure: BuildFailure { .unknownKeycode }
}

/// Switch to a layer while an app is frontmost.
public struct AppLayerRule: Identifiable, Hashable, Sendable, Codable {
    public var id: String
    public var appName: String
    public var bundleIdentifier: String
    /// Layer to activate (sent to the keyboard as a layer move over raw HID).
    public var layer: Int
    public var isEnabled: Bool
    /// SF Symbol stand-in for the app icon (snapshots can't load real app icons deterministically).
    public var symbolName: String

    public init(id: String, appName: String, bundleIdentifier: String, layer: Int, isEnabled: Bool = true, symbolName: String) {
        self.id = id
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.layer = layer
        self.isEnabled = isEnabled
        self.symbolName = symbolName
    }
}
