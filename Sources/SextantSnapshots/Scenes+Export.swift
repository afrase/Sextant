import SextantDomain
import SextantUI
import SwiftUI

extension Scenes {
    /// File ▸ Export ▸ Image (ADR 0044): always light, so one scene, on Sym+Num, whose colored chip and held activator
    /// show. The PDF's pages and Print Layout… draw the same board without cap shadows.
    static func export(_ f: Fixtures) async -> [SnapshotScene] {
        guard let layout = await model(f).session?.layout else { return [] }
        return [
            SnapshotScene("export-image-light", size: BoardImage.size(of: layout), chrome: .imageRenderer) {
                BoardImage(layout: layout, layer: 1)
            }
        ]
    }
}
