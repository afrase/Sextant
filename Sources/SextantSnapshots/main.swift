// Offscreen snapshot tool for design QA (spec §13.4). No TCC, no visible windows: see SnapshotRunner.swift.
//
//   swift run SextantSnapshots <output-dir> [--only a,b] [--scale 2]
//
// Scenes use the real adapters: the user's Oryx layout is imported into a throwaway library.

import Foundation
import SextantApplication
import SextantStorage
import SextantUI
import SwiftUI

let arguments = CommandLine.arguments
let outputDirectory = arguments.count > 1 && !arguments[1].hasPrefix("--") ? arguments[1] : "snapshots"
let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let layoutFile = repo.appending(path: "docs/research/oryx-examples/my-layout-KlgM7-40xJ7M.json")

let libraryRoot = FileManager.default.temporaryDirectory.appending(path: "sextant-snapshots-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: libraryRoot) }
let library = Library(store: PackageLibrary(root: libraryRoot, moveToTrash: { try FileManager.default.removeItem(at: $0) }))
let entry = try await library.importOryxJSON(Data(contentsOf: layoutFile))

/// A window model with the layout open on `layer`.
@MainActor func windowModel(layer: Int = 0, key: Int? = nil) async throws -> LayoutWindowModel {
    let model = LayoutWindowModel(library: library)
    await model.open(entry.id)
    model.session?.select(layer: layer)
    model.session?.select(key: key)
    return model
}

let main = try await windowModel()
let symNum = try await windowModel(layer: 1, key: 24)
let brdSys = try await windowModel(layer: 2)

var scenes: [SnapshotScene] = []
scenes += SnapshotScene.pair("window", size: CGSize(width: 1440, height: 900)) {
    LayoutWindow(model: main, layoutID: .constant(entry.id))
}
for (name, model) in [("main", main), ("symnum", symNum), ("brdsys", brdSys)] {
    scenes += SnapshotScene.pair("board-\(name)", size: CGSize(width: 1100, height: 560), chrome: .content) {
        if let session = model.session {
            BoardView(layout: session.layout, layer: session.selection.layer, selectedKey: session.selection.keyIndex)
                .background(Tokens.benchBase.color)
        }
    }
}

if let o = arguments.firstIndex(of: "--only"), arguments.indices.contains(o + 1) {
    let names = Set(arguments[o + 1].split(separator: ",").map(String.init))
    scenes = scenes.filter { names.contains($0.name) }
}
let scale = arguments.firstIndex(of: "--scale").flatMap { arguments.indices.contains($0 + 1) ? Double(arguments[$0 + 1]) : nil } ?? 2
try SnapshotRunner.run(scenes: scenes, outputDirectory: URL(fileURLWithPath: outputDirectory, isDirectory: true), scale: scale)
