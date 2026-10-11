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

/// A ``BoardCanvas`` that fits whatever space it's given (via `GeometryReader`), keeping the board's aspect ratio.
public struct FittedBoardCanvas<KeyContent: View>: View {
    public let geometry: BoardGeometry
    public let spacingRatio: CGFloat
    public let padding: CGFloat
    private let content: (BoardLayout.KeyFrame, BoardLayout) -> KeyContent

    public init(geometry: BoardGeometry = .voyager, spacingRatio: CGFloat = 0.1, padding: CGFloat = 0,
                @ViewBuilder key: @escaping (BoardLayout.KeyFrame, BoardLayout) -> KeyContent) {
        self.geometry = geometry
        self.spacingRatio = spacingRatio
        self.padding = padding
        self.content = key
    }

    public var body: some View {
        GeometryReader { proxy in
            let layout = geometry.layout(fitting: proxy.size, spacingRatio: spacingRatio, padding: padding)
            BoardCanvas(layout: layout) { f in content(f, layout) }
        }
        .aspectRatio(geometry.layout(keySize: 100, spacingRatio: spacingRatio, padding: padding).size, contentMode: .fit)
    }
}

extension BoardGeometry {
    /// Layout with `spacing = keySize * spacingRatio`.
    public func layout(keySize: CGFloat, spacingRatio: CGFloat, padding: CGFloat = 0) -> BoardLayout {
        layout(keySize: keySize, spacing: keySize * spacingRatio, padding: padding)
    }
}
