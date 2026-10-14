import Foundation
import SextantApplication
import SextantDomain
import SextantStorage
import SextantUI
import SwiftUI

extension Scenes {
    /// The Combos page (spec §6.4): the empty state, a few everyday combos with one selected, a dense board of 32 at full
    /// and minimum size, choosing keys for a new combo and its output, the "Keys from" filter, and ⌘K's Documents group.
    /// Every combo is built in code on the user's layout, which has none: other people's layouts never reach a scene.
    static func combos(_ f: Fixtures) async -> [SnapshotScene] {
        // A library of its own inside the fixtures' folder (removed with it), so the other scenes' sidebars don't list it.
        guard let root = await f.windowModel().library.location(of: f.entry.id)?.deletingLastPathComponent().appending(path: "combos"),
            let data = try? Data(contentsOf: Fixtures.layoutFile)
        else { return [] }
        /// The user's layout with combos added, saved before any window opens it.
        func layout(_ add: (EditSession) -> Void) async -> LibraryEntry? {
            let library = Library(store: PackageLibrary(root: root))
            guard let entry = try? await library.importOryxJSON(data), let session = try? await library.open(entry.id) else { return nil }
            add(session)
            await session.flush()
            await library.close(session)
            return entry
        }
        func open(_ entry: LibraryEntry) async -> LayoutWindowModel {
            let model = LayoutWindowModel(library: Library(store: PackageLibrary(root: root)))
            await model.open(entry.id)
            model.buildFlash = await idleBuildFlash(model)
            model.destination = .combos
            return model
        }
        /// A model per appearance: a pick or a picker belongs to one window.
        func pair(_ name: String, _ entry: LibraryEntry, size: CGSize = full, _ setUp: (LayoutWindowModel) -> Void) async -> [SnapshotScene]
        {
            var scenes: [SnapshotScene] = []
            for appearance in SnapshotAppearance.allCases {
                let model = await open(entry)
                setUp(model)
                scenes.append(
                    SnapshotScene("\(name)-\(appearance.rawValue)", size: size, appearance: appearance) {
                        LayoutWindow(model: model, layoutID: .constant(entry.id))
                    })
            }
            return scenes
        }
        let min = CGSize(width: 1120, height: 640)

        guard let empty = await layout({ _ in }), let everyday = await layout(everydayCombos), let dense = await layout(denseCombos)
        else { return [] }
        var scenes = await pair("combos-empty", empty) { _ in }
        scenes += await pair("combos", everyday) { _ in }
        scenes += await pair("combos-selected", everyday) { $0.selectCombo($0.session?.layout.combos.first?.id) }
        // A selected key keeps its combo number legible over the selection ring.
        scenes += await pair("combos-key-selected", everyday) {
            $0.selectCombo($0.session?.layout.combos.first?.id)
            $0.session?.select(key: 39)
        }
        scenes += await pair("combos-symnum", everyday) { $0.showCombos(fromLayer: 1) }
        scenes += await pair("combos-dense", dense) { _ in }
        scenes += await pair("combos-dense-min", dense, size: min) { _ in }
        scenes += await pair("combos-new", everyday) {
            $0.startNewCombo()
            $0.toggleDraftKey(13)
            $0.toggleDraftKey(14)
        }
        scenes += await pair("combos-new-output", everyday) {
            $0.startNewCombo()
            $0.toggleDraftKey(13)
            $0.toggleDraftKey(14)
            $0.chooseNewComboOutput()
        }
        scenes += await pair("combos-min", everyday, size: min) { $0.selectCombo($0.session?.layout.combos.last?.id) }
        scenes += await pair("palette-combos", everyday) { $0.openPalette(query: "combo") }
        return scenes
    }

    /// Combos someone might make on the user's layout: J + K for Esc, copy and paste under the left hand, and so on.
    private static func everydayCombos(_ session: EditSession) {
        session.setTitle("Everyday Combos")
        let combos: [([Int], Int, KeyAction, String?)] = [
            ([39, 40], 0, .code("KC_ESCAPE"), "Escape"),
            ([15, 16], 0, .code("KC_TAB"), nil),
            ([20, 21], 0, KeyAction(code: "KC_C", modifiers: [.leftCommand]), "Copy"),
            ([21, 22], 0, KeyAction(code: "KC_V", modifiers: [.leftCommand]), "Paste"),
            ([45, 46], 0, .code("KC_ENTER"), nil),
            ([16, 39], 0, .momentary(2), "Board"),
            ([8, 9, 10], 0, .code("KC_CAPS"), nil),
            ([38, 39], 1, .code("KC_LPRN"), nil),
            ([39, 40], 1, .code("KC_RPRN"), nil),
        ]
        for (keys, layer, output, name) in combos {
            let id = session.newCombo(keys: keys, layer: layer, output: output)
            if let name { session.renameCombo(id, to: name) }
        }
    }

    /// 32 combos, as dense as a busy Oryx layout: every pair of neighbours on the letter rows of both halves, and two across.
    private static func denseCombos(_ session: EditSession) {
        session.setTitle("Busy Combos")
        let outputs = ["KC_ESCAPE", "KC_ENTER", "KC_TAB", "KC_BSPC", "KC_DELETE", "KC_LBRC", "KC_RBRC", "KC_MINUS"]
        var count = 0
        for half in [0, 26] {
            for row in 1...3 {
                for column in 0..<5 {
                    let first = half + row * 6 + column
                    session.newCombo(keys: [first, first + 1], layer: 0, output: .code(outputs[count % outputs.count]))
                    count += 1
                }
            }
        }
        session.newCombo(keys: [16, 39], layer: 0, output: KeyAction(code: "KC_C", modifiers: [.leftCommand]))
        session.newCombo(keys: [14, 15, 16, 39, 40, 41], layer: 0, output: .momentary(2))
    }
}
