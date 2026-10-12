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
        guard let root = await f.windowModel().library.location(of: f.entry.id)?.deletingLastPathComponent().appending(path: "macros"),
            let jr = await importExample("voyager-JRGQm.json", into: root),
            let xl = await importExample("voyager-XlrR4.json", into: root)
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

        var scenes = await pair("macros-jrgqm", jr) { $0.session?.selectMacro(teamsCam, step: 1) }
        scenes += await pair("macros-jrgqm-min", jr, size: min) { $0.session?.selectMacro(teamsCam, step: 0) }
        scenes += await pair("macros-xlrr4", xl) { $0.session?.selectMacro(.key(KeyRef(layer: 3, index: 6, slot: .tap)), step: 2) }
        scenes += await pair("macros-empty", f.entry, make: { await model(f) }) { $0.destination = .macros }
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
