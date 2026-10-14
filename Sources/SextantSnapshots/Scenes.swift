import SextantApplication
import SextantDomain
import SextantStorage
import SextantUI
import SwiftUI

/// The design-QA scene list (spec §13.4). Names are stable: `<surface>-<variant>-<light|dark>`.
@MainActor
enum Scenes {
    static let full = CGSize(width: 1440, height: 900)
    static let connected = ActivityState.Device.connected(serial: "KlgM7/40xJ7M", matchesLayout: true)

    static func all(_ f: Fixtures) async -> [SnapshotScene] {
        var scenes: [SnapshotScene] = []
        func window(_ name: String, _ model: LayoutWindowModel, size: CGSize = full, light: Bool = false) {
            let make = { LayoutWindow(model: model, layoutID: .constant(f.entry.id)) }
            scenes += light ? [SnapshotScene("\(name)-light", size: size) { make() }] : SnapshotScene.pair(name, size: size) { make() }
        }

        // Main with Z (key 19) selected; a keyboard connected that runs an older revision.
        let main = await model(f, key: 19)
        main.activity = ActivityState(device: connected, status: .notOnKeyboard(edits: 5))
        window("window", main)

        // Each layer. Sym+Num with ⏎ selected shows the context strip; an edit (made last, below) adds " · Edited".
        let symNum = await model(f, layer: 1, key: 24)
        window("window-symnum", symNum)
        window("window-brdsys", await model(f, layer: 2))

        // Following the keyboard with keys down; building (Stop, spinner, hairline).
        let follow = await model(f, layer: 2)
        follow.activity = ActivityState(device: connected, status: .onKeyboard(revisionDate: Date(timeIntervalSince1970: 1_789_000_000)))
        follow.isFollowing = true
        follow.pressedKeys.update([51, 13, 14])
        window("window-follow", follow)
        let building = await model(f, key: 24)
        building.activity = ActivityState(device: connected, status: .building(file: "keymap.c", done: 12, total: 41))
        window("window-building", building, light: true)

        // Honest minimums (spec §3.2): both columns at 1120×640, neither at 640×640.
        window("window-min-both", await model(f, layer: 1, key: 19), size: CGSize(width: 1120, height: 640))
        // Edits restored from the recovery copy (ADR 0032), at the minimum width.
        let recovered = await model(f, layer: 1, key: 19)
        recovered.session?.recoveredUnsavedChanges = true
        window("window-recovered-min", recovered, size: CGSize(width: 1120, height: 640), light: true)
        let bare = await model(f, layer: 1, key: 19)
        bare.columnVisibility = .detailOnly
        bare.showsInspector = false
        window("window-min-none", bare, size: CGSize(width: 640, height: 640))

        // Legend modes and the Lighting lens.
        for mode in [LegendMode.qmk, .index] {
            let m = await model(f, layer: 2, key: 31)
            m.legendMode = mode
            window("window-\(mode.rawValue)", m)
        }
        let lighting = await model(f, layer: 2)
        lighting.lens = .lighting
        window("window-lighting", lighting, light: true)

        scenes += await boards(f)
        scenes += await inspector(f)
        scenes += await picker(f)
        // Before any scene edits the shared layout, so none of its windows opens on a recovery copy.
        scenes += await multiSelect(f)
        scenes += await `import`(f)
        scenes += await device(f)
        scenes += await settings(f)
        scenes += await layerShortcuts(f)
        scenes += await menuBar(f)
        scenes += SnapshotScene.pair("activity", size: CGSize(width: 480, height: 14 * 40 + 16), chrome: .content) { activityStates }
        scenes += await layers(f)
        scenes += await export(f)
        scenes += await macros(f)
        scenes += await combos(f)
        scenes += await history(f)
        scenes += await firmwareSettings(f)
        // The app icon, 1024 pt on a transparent canvas, one scene per detail tier (app-icon serves 128 px and up);
        // scripts/icon renders each at its pixel size into Resources/AppIcon.icns.
        for (name, pixels) in [("app-icon", 1024.0), ("app-icon-64", 64), ("app-icon-32", 32), ("app-icon-16", 16)] {
            scenes.append(
                SnapshotScene(name, size: CGSize(width: 1024, height: 1024), chrome: .imageRenderer, background: .transparent) {
                    AppIconArtwork(pixels: pixels)
                })
        }
        // After every model has loaded, so the autosave of this edit can't leak into other scenes.
        symNum.session?.setColor(HexColor(hex: "#FF9500"), layer: 1, index: 30)
        return scenes
    }

    /// The fixtures' window model with Build & Flash wired to a no-op, so it draws enabled.
    static func model(_ f: Fixtures, layer: Int = 0, key: Int? = nil) async -> LayoutWindowModel {
        let model = await f.windowModel(layer: layer, key: key)
        model.buildFlash = await idleBuildFlash(model)
        return model
    }

    // MARK: Boards

    static func boards(_ f: Fixtures) async -> [SnapshotScene] {
        var scenes: [SnapshotScene] = []
        let size = CGSize(width: 1100, height: 560)
        for (name, layer) in [("main", 0), ("symnum", 1), ("brdsys", 2)] {
            guard let session = await model(f, layer: layer).session else { continue }
            scenes += SnapshotScene.pair("board-\(name)", size: size, chrome: .content) { board(session) }
        }
        // Every kind in §4.4, with issues and live presses, on a copy of the user's layout.
        // A session of its own, outside the library, so windows don't list it. It is never edited, so never saved.
        guard let base = await model(f).session else { return scenes }
        let entry = LibraryEntry(id: UUID(), title: "Every kind", origin: .local, modifiedAt: Date())
        let kinds = EditSession(
            stored: StoredLayout(entry: entry, layout: kindsLayout(base.layout), contentHash: "", revisions: []),
            library: PackageLibrary(root: FileManager.default.temporaryDirectory.appending(path: "sextant-unused")))
        kinds.select(key: 15)
        let issues: [KeyRef: LayoutIssue.Severity] = [KeyRef(layer: 0, index: 3): .error, KeyRef(layer: 0, index: 9): .warning]
        let pressed = PressedKeys()
        pressed.update([20, 24])
        scenes += SnapshotScene.pair("board-kinds", size: size, chrome: .content) { board(kinds, issues: issues, pressed: pressed) }
        // Accessibility variants (spec §11) are board scenes: NavigationSplitView columns don't inherit injected
        // accessibility settings. Reduce Transparency looks like every snapshot, which always draws opaque surfaces.
        scenes.append(
            SnapshotScene("board-kinds-dwc-light", size: size, chrome: .content) {
                board(kinds, issues: issues, pressed: pressed).environment(\._accessibilityDifferentiateWithoutColor, true)
            })
        scenes += SnapshotScene.pair("board-kinds-contrast", size: size, chrome: .content) {
            board(kinds, issues: issues, pressed: pressed).environment(\._colorSchemeContrast, .increased)
        }
        if let symNum = await model(f, layer: 1, key: 24).session {
            scenes += SnapshotScene.pair("board-symnum-contrast", size: size, chrome: .content) {
                board(symNum).environment(\._colorSchemeContrast, .increased)
            }
        }
        return scenes
    }

    static func board(_ session: EditSession, issues: [KeyRef: LayoutIssue.Severity] = [:], pressed: PressedKeys? = nil) -> some View {
        BoardView(session: session, issues: issues, pressed: pressed).background(Tokens.benchBase.color)
    }

    /// The user's base layer with keys swapped for one of every kind and state (spec §4.4).
    static func kindsLayout(_ layout: KeyboardLayout) -> KeyboardLayout {
        var layout = layout
        let replacements: [Int: Key] = [
            0: Key(tap: .code("KC_A"), doubleTap: .code("KC_B")),
            1: Key(tap: .code("KC_C"), hold: .code("KC_LEFT_SHIFT"), doubleTap: .code("KC_D")),
            2: .none,
            3: Key("KC_FOO"),
            4: Key(tap: KeyAction(code: "KC_TRANSPARENT", macro: Macro(name: "Open Keymap", steps: [MacroStep(code: "KC_K")]))),
            5: Key(tap: .code("KC_LBRC", modifiers: [.leftCommand, .leftShift]), customLabel: "Prev Tab"),
            6: Key(tap: .momentary(1)), 7: Key(tap: .toggle(2)), 8: Key(tap: .moveTo(1)), 9: Key(tap: KeyAction(code: "TT", layer: 2)),
            10: Key(tap: .oneShotLayer(1)),
            11: Key(tap: .setColor(HexColor(red: 1, green: 0.18, blue: 0.33))),
            12: Key(tap: .code("KC_Q"), glowColor: HexColor(red: 0, green: 0.78, blue: 0.75)),
            13: Key("QK_BOOT"),
            14: Key(hold: .code("KC_LEFT_CTRL")),
            15: Key(tap: .code("KC_F"), hold: .momentary(2)),
            16: Key(tap: .code("KC_G"), hold: .code("KC_ESCAPE")),
            17: Key("RGB_TOG"),
        ]
        for (index, key) in replacements { layout.layers[0].keys[index] = key }
        return layout
    }

    // MARK: Activity capsule

    static var activityStates: some View {
        let states: [ActivityState] = [
            ActivityState(),
            ActivityState(device: connected, status: .onKeyboard(revisionDate: Date(timeIntervalSince1970: 1_789_000_000))),
            ActivityState(device: connected, status: .notOnKeyboard(edits: 5)),
            ActivityState(device: .connected(serial: "Q9x2/aa11", matchesLayout: false), status: .otherLayout(serial: "Q9x2/aa11")),
            ActivityState(device: .connected(serial: nil, matchesLayout: true), status: .heldByAnotherApp("Keymapp")),
            ActivityState(device: connected, status: .issues(count: 2, firstKey: 45)),
            ActivityState(device: connected, status: .building(file: "keymap.c", done: 12, total: 41)),
            ActivityState(device: connected, status: .built(bytes: 65_786, percentOfFlash: 54)),
            ActivityState(device: connected, status: .waitingForFlashMode),
            ActivityState(device: .flashMode, status: .writing(fraction: 0.64, bytes: 41_984)),
            ActivityState(device: .flashMode, status: .verifying),
            ActivityState(device: connected, status: .flashed(revision: "40xJ7M")),
            ActivityState(device: connected, status: .buildFailed(errors: 1, key: 45)),
            ActivityState(device: .flashMode, status: .flashFailed),
        ]
        return VStack(spacing: 8) {
            ForEach(Array(states.enumerated()), id: \.offset) { _, state in
                ActivityCapsule(state: state, boardName: "ZSA Voyager", onShowLog: {})
                    .frame(width: 440, height: 32)
                    .background(Capsule().fill(Tokens.surface.color))
            }
        }
        .padding(8)
    }
}
