import SextantDomain
import SwiftUI

/// Places one view per key at its frame (size, rotation, position). No styling: you supply every key view.
///
/// ```swift
/// let layout = BoardGeometry.voyager.layout(keySize: 54, spacing: 6, padding: 12)
/// BoardCanvas(layout: layout) { frame in
///     MyKeyCap(legend: Legends.legend(layout: doc, layer: 0, index: frame.index))
/// }
/// ```
/// The key view is sized to the cap before rotation, so draw it upright; the canvas rotates the thumbs.
public struct BoardCanvas<KeyContent: View>: View {
    public let layout: BoardLayout
    private let content: (BoardLayout.KeyFrame) -> KeyContent

    public init(layout: BoardLayout, @ViewBuilder key: @escaping (BoardLayout.KeyFrame) -> KeyContent) {
        self.layout = layout
        self.content = key
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout.frames) { f in
                content(f)
                    .frame(width: f.size.width, height: f.size.height)
                    .rotationEffect(.degrees(f.rotation))
                    .position(f.center)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
    }
}
