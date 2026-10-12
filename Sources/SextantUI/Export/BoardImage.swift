import AppKit
import SextantApplication
import SextantDomain
import SwiftUI

/// One layer of a layout as a picture, for File ▸ Export and Print Layout… (spec §9.1): the layout's title and the
/// layer's name over its board, on Sextant's own geometry. No selection, issues, presses or halos, always light, on
/// white, so it reads the same on screen and on paper.
public struct BoardImage: View {
    var layout: KeyboardLayout
    var layer: Int
    var mode: LegendMode

    public init(layout: KeyboardLayout, layer: Int, mode: LegendMode = .symbols) {
        self.layout = layout
        self.layer = layer
        self.mode = mode
    }

    private static let cap: CGFloat = 54
    private static let padding: CGFloat = 32
    private static let header: CGFloat = 44

    /// The image's size in whole points, the same for every layer of a layout.
    public static func size(of layout: KeyboardLayout) -> CGSize {
        let board = board(of: layout).size
        return CGSize(width: (board.width + 2 * padding).rounded(.up), height: (header + board.height + 2 * padding).rounded(.up))
    }

    private static func board(of layout: KeyboardLayout) -> BoardLayout {
        EditSession.geometry(of: layout).layout(keySize: cap, spacing: cap * 0.11)
    }

    public var body: some View {
        let board = Self.board(of: layout)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                LayerChip(color: layout.layers[safe: layer]?.color, size: 14)
                Text(verbatim: layout.title).font(.system(size: 20, weight: .semibold))
                Text(verbatim: layout.layers[safe: layer]?.title ?? "").font(.system(size: 20)).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            ZStack(alignment: .topLeading) {
                if let kind = layout.navigator?.kind, let nav = board.navigator {
                    NavigatorDisc(diameter: nav.diameter, kind: kind).position(nav.center)
                }
                BoardCanvas(layout: board) { frame in
                    KeyCap(
                        model: KeyCapModel(layout: layout, layer: layer, index: frame.index, mode: mode), u: Self.cap,
                        height: frame.size.height)
                }
            }
            .frame(width: board.size.width, height: board.size.height)
        }
        .padding(Self.padding)
        .frame(width: Self.size(of: layout).width, height: Self.size(of: layout).height)
        .background(.white)
        .environment(\.colorScheme, .light)
    }
}

extension BoardImage {
    /// The shown layer as a PNG at 2x, marked 144 dpi so it opens at its point size.
    static func png(_ layout: KeyboardLayout, layer: Int, mode: LegendMode) -> Data? {
        let renderer = ImageRenderer(content: BoardImage(layout: layout, layer: layer, mode: mode))
        renderer.scale = 2
        guard let image = renderer.cgImage else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = size(of: layout)
        return rep.representation(using: .png, properties: [:])
    }

    /// Every layer, one page each, drawn into a PDF context so legends stay text and caps stay paths (Print Layout…
    /// prints it too). The caps cast no shadows: the PDF's would print as grey boxes.
    static func pdf(_ layout: KeyboardLayout, mode: LegendMode) -> Data? {
        let data = NSMutableData()
        var page = CGRect(origin: .zero, size: size(of: layout))
        guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &page, nil) else {
            return nil
        }
        for layer in layout.layers.indices {
            let image = BoardImage(layout: layout, layer: layer, mode: mode).environment(\.capShadows, false)
            ImageRenderer(content: image).render { _, draw in
                context.beginPage(mediaBox: &page)
                draw(context)
                context.endPage()
            }
        }
        context.closePDF()
        return data as Data
    }
}
