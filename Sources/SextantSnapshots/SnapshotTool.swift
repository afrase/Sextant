// Offscreen snapshot tool for design QA (spec §13.4). No TCC, no visible windows: see SnapshotRunner.swift.
//
//   swift run SextantSnapshots <output-dir> [--only window-light,board-main-dark] [--scale 2] [--list]
//
// Scenes use the real adapters: the user's Oryx layout is imported into a throwaway library.

import ArgumentParser
import Foundation
import SextantApplication
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

    static func load() async throws -> Self {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let layoutFile = repo.appending(path: "docs/research/oryx-examples/my-layout-KlgM7-40xJ7M.json")
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

    func cleanUp() { try? FileManager.default.removeItem(at: root) }
}
