import SextantUI
import SwiftUI

/// The design-QA scene list (spec §13.4). Names are stable: `<surface>-<variant>-<light|dark>`.
@MainActor
enum Scenes {
    static func all(_ f: Fixtures) async -> [SnapshotScene] {
        let main = await f.windowModel()
        let symNum = await f.windowModel(layer: 1, key: 24)
        let brdSys = await f.windowModel(layer: 2)
        var scenes: [SnapshotScene] = []
        scenes += SnapshotScene.pair("window", size: CGSize(width: 1440, height: 900)) {
            LayoutWindow(model: main, layoutID: .constant(f.entry.id))
        }
        for (name, model) in [("main", main), ("symnum", symNum), ("brdsys", brdSys)] {
            scenes += SnapshotScene.pair("board-\(name)", size: CGSize(width: 1100, height: 560), chrome: .content) {
                if let session = model.session {
                    BoardView(layout: session.layout, layer: session.selection.layer, selectedKey: session.selection.keyIndex)
                        .background(Tokens.benchBase.color)
                }
            }
        }
        return scenes
    }
}
