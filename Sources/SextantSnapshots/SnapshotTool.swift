// Offscreen snapshot tool for design QA (spec §13.4). No TCC, no visible windows: see SnapshotRunner.swift.
//
//   swift run SextantSnapshots <output-dir> [--only window-light,board-main-dark] [--scale 2] [--list]
//
// Scenes use the real adapters: the user's Oryx layout is imported into a throwaway library.

import ArgumentParser
import Foundation
import SextantApplication
import SextantDomain
import SextantStorage
import SextantUI
import SwiftUI

@main
struct SnapshotTool: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "SextantSnapshots", abstract: "Render Sextant's design-QA scenes offscreen to PNG files.")

    @Argument(help: "Folder for the PNG files.")
    var output = "snapshots"

    @Option(help: "Comma-separated scene names to render (default: all).")
    var only: String?

    @Option(help: "Pixel scale.")
    var scale: Double = 2

    @Flag(help: "List the scene names and exit.")
    var list = false

    @MainActor
    func run() async throws {
        let fixtures = try await Fixtures.load()
        defer { fixtures.cleanUp() }
        var scenes = await Scenes.all(fixtures)
        if list {
            scenes.map(\.name).forEach { print($0) }
            return
        }
        if let only {
            let names = Set(only.split(separator: ",").map(String.init))
            scenes = scenes.filter { names.contains($0.name) }
        }
        try SnapshotRunner.run(scenes: scenes, outputDirectory: URL(fileURLWithPath: output, isDirectory: true), scale: scale)
    }
}

/// The user's layout in a throwaway library, plus window models opened on it.
@MainActor
struct Fixtures {
    let entry: LibraryEntry
    private let root: URL

    static let layoutFile = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "docs/research/oryx-examples/my-layout-KlgM7-40xJ7M.json")

    static func load() async throws -> Self {
        let root = FileManager.default.temporaryDirectory.appending(path: "sextant-snapshots-\(UUID().uuidString)")
        let library = Library(store: PackageLibrary(root: root, moveToTrash: { try FileManager.default.removeItem(at: $0) }))
        let entry = try await library.importOryxJSON(Data(contentsOf: layoutFile))
        return Self(entry: entry, root: root)
    }

    /// A window model with the layout open on `layer`, optionally with a key selected. Each gets its own `Library`
    /// over the same folder, because a library opens a layout in one window only (ADR 0026).
    func windowModel(layer: Int = 0, key: Int? = nil) async -> LayoutWindowModel {
        let model = LayoutWindowModel(library: Library(store: PackageLibrary(root: root)))
        await model.open(entry.id)
        model.session?.select(layer: layer)
        model.session?.select(key: key)
        return model
    }

    /// The user's layout with History to show (ADR 0043), in a library of its own so other scenes never see it. Revision 2
    /// edits five keys on Brd+Sys (three changed, one added, one removed), revision 3 changes a setting, and the working
    /// copy has an edit since. The keyboard runs revision 1, Oryx's build, with live access off.
    func editedRevisionModel() async -> LayoutWindowModel? {
        let store = PackageLibrary(root: FileManager.default.temporaryDirectory.appending(path: "sextant-snapshots-\(UUID().uuidString)"))
        let library = Library(store: store)
        guard let data = try? Data(contentsOf: Self.layoutFile), let entry = try? await library.importOryxJSON(data) else { return nil }
        let keyboard = PluggedInKeyboard(serial: "KlgM7/40xJ7M")
        let live = LiveSession(watcher: keyboard, link: keyboard, secureInputProbe: { false })
        live.start()
        let onKeyboard = OnKeyboard(library: library, store: store, live: live)
        onKeyboard.start()
        let model = LayoutWindowModel(library: library, onKeyboard: onKeyboard)
        await model.open(entry.id)
        guard let session = model.session else { return nil }
        session.setCode("KC_BRIGHTNESS_DOWN", layer: 2, index: 8)
        session.setCode("KC_BRIGHTNESS_UP", layer: 2, index: 9)
        session.setColor(HexColor(hex: "#FF9500"), layer: 2, index: 16)
        session.setCode("KC_PSCR", layer: 2, index: 36)
        session.makeTransparent(layer: 2, index: 10)
        _ = try? await session.saveRevision(source: .save, message: "Edited 5 keys on Brd+Sys")
        session.setSetting("tappingTerm", to: .number(180))
        _ = try? await session.saveRevision(source: .save, message: "Tapping term 180 ms")
        session.setCode("KC_F13", layer: 0, index: 0)
        await session.flush()
        for _ in 0..<100 where onKeyboard.running?.revision == nil { try? await Task.sleep(for: .milliseconds(50)) }
        return model
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }
}
