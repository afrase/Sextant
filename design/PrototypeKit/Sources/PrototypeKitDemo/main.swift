// PrototypeKitDemo
//
//   swift run PrototypeKitDemo [--snapshot <dir>] [--only a,b] [--check]
//
// With no flags: runs the self-checks and writes all demo snapshots to ./snapshots.
// --check: self-checks only. --snapshot <dir>: snapshots only (the standard flag every prototype supports).

import AppKit
import SwiftUI
import PrototypeKit

@MainActor
enum DemoScenes {
    static var all: [SnapshotScene] {
        var scenes: [SnapshotScene] = []
        // The required demo: a neutral board of the user's Main layer.
        for a in SnapshotAppearance.allCases {
            scenes.append(SnapshotScene("board-main-\(a.rawValue)", size: CGSize(width: 1160, height: 500), appearance: a,
                                        chrome: .imageRenderer, background: .windowBackground) {
                NeutralBoard(layer: 0, keySize: 58).frame(maxWidth: .infinity, maxHeight: .infinity)
            })
        }
        scenes.append(SnapshotScene("board-brdsys-light", size: CGSize(width: 1160, height: 500), chrome: .imageRenderer) {
            NeutralBoard(layer: 2, keySize: 58).frame(maxWidth: .infinity, maxHeight: .infinity)
        })
        scenes.append(SnapshotScene("board-indices-light", size: CGSize(width: 1160, height: 500), chrome: .imageRenderer) {
            NeutralBoard(layer: 1, keySize: 58, pressed: MockDevice.frozen(at: 4.6).pressedKeys, showIndices: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        })
        // Window path: sidebar, toolbar, inspector, both appearances.
        scenes += SnapshotScene.pair("window", size: CGSize(width: 1460, height: 760)) { DemoWindow() }
        // Overlays composited over a window.
        scenes.append(SnapshotScene("window-sheet-light", size: CGSize(width: 1460, height: 760),
                                    overlays: [.sheet(width: 560) { ImportSheet() }]) { DemoWindow() })
        scenes.append(SnapshotScene("window-popover-dark", size: CGSize(width: 1460, height: 760), appearance: .dark,
                                    overlays: [
                                        .popover(size: CGSize(width: 300, height: 150), anchor: CGRect(x: 660, y: 480, width: 44, height: 44), edge: .bottom) { KeyPopover() },
                                        .menu(size: CGSize(width: 200, height: 160), at: CGPoint(x: 120, y: 120)) { LayerMenu() },
                                    ]) { DemoWindow(layer: 2, selectedKey: 31) })
        // Glass on the two windowless paths, for comparison.
        for (name, chrome) in [("glass-content", SnapshotScene.Chrome.content), ("glass-imagerenderer", .imageRenderer)] {
            for a in SnapshotAppearance.allCases {
                scenes.append(SnapshotScene("\(name)-\(a.rawValue)", size: CGSize(width: 520, height: 260), appearance: a, chrome: chrome) {
                    GlassProbe()
                })
            }
        }
        return scenes
    }
}

let args = CommandLine.arguments
SnapshotRunner.handleCommandLine(DemoScenes.all)
let failures = runChecks()
if !args.contains("--check") {
    let out = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("snapshots")
    do {
        try SnapshotRunner.run(scenes: DemoScenes.all, outputDirectory: out)
    } catch {
        print("snapshot error: \(error)")
        exit(1)
    }
}
exit(failures == 0 ? 0 : 2)
