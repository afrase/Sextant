import Foundation
import SextantApplication
import SextantDomain
import SextantStorage
import SextantUI
import SwiftUI

extension Scenes {
    /// The Macros page (spec §6.3): JRGQm's 67 macros and XlrR4's Alt-code ones, the empty state, the step inspector and
    /// its picker, Record Steps, Assign to Key's capsule on the board, and ⌘K's Documents group.
    static func macros(_ f: Fixtures) async -> [SnapshotScene] {
        // A library of its own inside the fixtures' folder (removed with it), so the other scenes' sidebars don't list it.
        guard let root = await f.windowModel().library.location(of: f.entry.id)?.deletingLastPathComponent().appending(path: "macros")
        else { return [] }
        func open(_ entry: LibraryEntry) async -> LayoutWindowModel {
            let model = LayoutWindowModel(library: Library(store: PackageLibrary(root: root)))
            await model.open(entry.id)
            model.buildFlash = await idleBuildFlash(model)
            model.destination = .macros
            return model
        }
        /// A model per appearance: leaving the page ends Record Steps, so the light window's close would end the dark one's.
        func pair(
            _ name: String, _ entry: LibraryEntry, size: CGSize = full, make: (() async -> LayoutWindowModel)? = nil,
            _ setUp: (LayoutWindowModel) -> Void
        ) async -> [SnapshotScene] {
            var scenes: [SnapshotScene] = []
            for appearance in SnapshotAppearance.allCases {
                let model = if let make { await make() } else { await open(entry) }
                setUp(model)
                scenes.append(
                    SnapshotScene("\(name)-\(appearance.rawValue)", size: size, appearance: appearance) {
                        LayoutWindow(model: model, layoutID: .constant(entry.id))
                    })
            }
            return scenes
        }
        /// "Teams Cam" on JRGQm's AppMedia key 32: ⌃⌘1, ⌃⌘2 and ⌃⇧O, 100 ms apart.
        let teamsCam = MacroLocator.key(KeyRef(layer: 2, index: 32, slot: .tap))
        let brackets = MacroLocator.key(KeyRef(layer: 1, index: 35, slot: .tap))
        let min = CGSize(width: 1120, height: 640)

        // The empty page is the user's layout; so is the dense one, with macros added in code. The rest need other
        // people's samples (under $SEXTANT_REFERENCE).
        var scenes = await pair("macros-empty", f.entry, make: { await model(f) }) { $0.destination = .macros }
        for (name, size, picker) in [("macros-dense-min", min, false), ("macros-dense-picker", full, true)] {
            for appearance in SnapshotAppearance.allCases {
                // A library per scene, so each window edits its own copy and the sidebar lists only that one.
                let own = root.deletingLastPathComponent().appending(path: "\(name)-\(appearance.rawValue)")
                guard let mine = await importExample("my-layout-KlgM7-40xJ7M.json", into: own) else { continue }
                let model = LayoutWindowModel(library: Library(store: PackageLibrary(root: own)))
                await model.open(mine.id)
                model.buildFlash = await idleBuildFlash(model)
                model.destination = .macros
                guard let locator = model.session.flatMap(addDenseMacros) else { continue }
                if picker { model.openStepPicker(step: 2, in: locator) }
                scenes.append(
                    SnapshotScene("\(name)-\(appearance.rawValue)", size: size, appearance: appearance) {
                        LayoutWindow(model: model, layoutID: .constant(mine.id))
                    })
            }
        }
        guard let jr = await importExample("voyager-JRGQm.json", into: root), let xl = await importExample("voyager-XlrR4.json", into: root)
        else { return scenes }
        scenes += await pair("macros-jrgqm", jr) { $0.session?.selectMacro(teamsCam, step: 1) }
        scenes += await pair("macros-jrgqm-min", jr, size: min) { $0.session?.selectMacro(teamsCam, step: 0) }
        scenes += await pair("macros-xlrr4", xl) { $0.session?.selectMacro(.key(KeyRef(layer: 3, index: 6, slot: .tap)), step: 2) }
        scenes += await pair("macros-step-picker", jr) {
            $0.session?.selectMacro(teamsCam, step: 1)
            $0.openStepPicker(step: 1, in: teamsCam)
        }
        scenes += await pair("macros-recording-min", xl, size: min) {
            $0.session?.selectMacro(brackets, step: 6)
            $0.startRecordingSteps(in: brackets)
        }
        scenes += await pair("macros-assign", jr) {
            $0.session?.select(layer: 2)
            $0.assignMacroToKey(teamsCam)
        }
        // ⌘K's Documents group finds macros by title.
        scenes += await pair("palette-macros", jr) { $0.openPalette(query: "teams") }
        return scenes
    }

    /// Macros built in code on the user's layout (which has none), for the widest cells the page draws: a long name with
    /// descenders, and steps holding two, three and four modifiers. Returns the first, on the Brd+Sys key 32's tap, with
    /// its third step selected.
    private static func addDenseMacros(_ session: EditSession) -> MacroLocator? {
        func add(_ name: String, _ steps: [MacroStep], on index: Int) {
            session.newMacro()
            guard let draft = session.selection.macro else { return }
            for (at, step) in steps.enumerated() { session.insertStep(step, at: at, in: draft) }
            session.renameMacro(draft, to: name)
            session.assignMacro(draft, layer: 2, index: index)
        }
        add(
            "Typography quickly: jump, paste, apply styling, and play back my gigantic yearly signature",
            [
                MacroStep(code: "KC_1", modifiers: [.leftControl, .leftCommand], delay: 100),
                MacroStep(code: "KC_2", modifiers: [.leftControl, .leftCommand], delay: 100),
                MacroStep(code: "KC_O", modifiers: [.leftControl, .leftShift, .leftCommand], delay: 250),
                MacroStep(code: "KC_F12", modifiers: [.leftControl, .leftOption, .leftShift, .leftCommand]),
                MacroStep(code: "KC_V", modifiers: [.leftCommand], delay: 30),
                MacroStep(code: "KC_ENTER"),
            ], on: 32)
        add(
            "Copy line",
            [
                MacroStep(code: "KC_HOME"), MacroStep(code: "KC_END", modifiers: [.leftShift]),
                MacroStep(code: "KC_C", modifiers: [.leftCommand]),
            ], on: 33)
        add("Spotlight", [MacroStep(code: "KC_SPACE", modifiers: [.leftCommand], delay: 200)], on: 34)
        let first = MacroLocator.key(KeyRef(layer: 2, index: 32, slot: .tap))
        guard session.layout.macro(at: first) != nil else { return nil }
        session.selectMacro(first, step: 2)
        return first
    }

    private static func importExample(_ file: String, into root: URL) async -> LibraryEntry? {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let path = "docs/research/oryx-examples/\(file)"
        // Other people's samples are kept out of the repo, at the same path under $SEXTANT_REFERENCE; without it, no scenes.
        let reference = ProcessInfo.processInfo.environment["SEXTANT_REFERENCE"].map { URL(fileURLWithPath: $0).appending(path: path) }
        guard let data = (try? Data(contentsOf: repo.appending(path: path))) ?? reference.flatMap({ try? Data(contentsOf: $0) })
        else { return nil }
        return try? await Library(store: PackageLibrary(root: root)).importOryxJSON(data)
    }
}
