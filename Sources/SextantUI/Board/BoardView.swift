import SextantDomain
import SwiftUI

/// The keyboard for one layer, fitted into whatever space it gets (spec §3.3, §4).
///
/// The frame is a pure function of the available size, so nothing outside the board area can move it.
public struct BoardView: View {
    var layout: KeyboardLayout
    var layer: Int
    var selectedKey: Int?
    var mode: LegendMode
    var capRange: ClosedRange<CGFloat>
    var onSelect: ((Int) -> Void)?

    public init(
        layout: KeyboardLayout, layer: Int, selectedKey: Int? = nil, mode: LegendMode = .symbols,
        capRange: ClosedRange<CGFloat> = 36...76, onSelect: ((Int) -> Void)? = nil
    ) {
        self.layout = layout
        self.layer = layer
        self.selectedKey = selectedKey
        self.mode = mode
        self.capRange = capRange
        self.onSelect = onSelect
    }

    /// Cap side for a board area (spec §3.3). The spec's `pitch = min((W − 48) / 15, (H − 48) / 6.7)` uses the
    /// Voyager's size in pitch units; any board passes its own (ADR 0017). `cap = pitch / 1.11`, clamped.
    static func capSize(for area: CGSize, boardUnits: CGSize, range: ClosedRange<CGFloat>) -> CGFloat {
        let pitch = min((area.width - 48) / boardUnits.width, (area.height - 48) / boardUnits.height)
        return min(max(pitch / 1.11, range.lowerBound), range.upperBound)
    }

    public var body: some View {
        GeometryReader { proxy in
            let geometry = (layout.board ?? .voyager).geometry(navigator: layout.navigator.map { $0.side == .left ? .left : .right })
            let cap = Self.capSize(for: proxy.size, boardUnits: geometry.bounds.size, range: capRange)
            let board = geometry.layout(keySize: cap, spacing: cap * 0.11)
            let models = capModels()
            ZStack(alignment: .topLeading) {
                if layout.navigator != nil, let nav = board.navigator {
                    NavigatorDisc(diameter: nav.diameter, kind: layout.navigator?.kind)
                        .position(nav.center)
                }
                BoardCanvas(layout: board) { frame in
                    if let model = models[safe: frame.index] {
                        KeyCap(model: model, u: cap)
                            .equatable()
                            .onTapGesture { onSelect?(frame.index) }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(model.accessibilityLabel)
                            .accessibilityAddTraits(frame.index == selectedKey ? [.isButton, .isSelected] : .isButton)
                    }
                }
            }
            .frame(width: board.size.width, height: board.size.height)
            .position(x: proxy.size.width / 2, y: proxy.size.height * 0.46)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Keyboard, \(layerName) layer, \(layout.keyCount) keys"))
    }

    private var layerName: String { layout.layers.indices.contains(layer) ? layout.layers[layer].title : "" }

    private func capModels() -> [KeyCapModel] {
        let tones = layer > 0 ? layout.layers[safe: layer]?.color.map(LayerTones.init) : nil
        var targetTones: [Int: LayerTones] = [:]
        for (i, l) in layout.layers.enumerated() { if let c = l.color { targetTones[i] = LayerTones(c) } }
        return (0..<layout.keyCount).map { index in
            let legend = Legends.legend(layout: layout, layer: layer, index: index)
            return KeyCapModel(
                index: index, legend: legend, layerTones: tones,
                holdTargetTones: legend.legend.secondary?.layer.flatMap { targetTones[$0] },
                isSelected: index == selectedKey, mode: mode)
        }
    }
}

/// The recessed, non-interactive Navigator disc (spec §4.1).
private struct NavigatorDisc: View {
    var diameter: CGFloat
    var kind: NavigatorConfig.Kind?

    var body: some View {
        Circle()
            .fill(Tokens.ghostFill.color)
            .overlay { Circle().strokeBorder(Tokens.ghostStroke.color, lineWidth: 1) }
            .overlay {
                Image(systemName: kind == .trackball ? "circle.circle" : "rectangle.and.hand.point.up.left")
                    .font(.system(size: diameter * 0.32))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: diameter, height: diameter)
            .help(String(localized: "Navigator · settings in Firmware Settings › Navigator"))
            .accessibilityHidden(true)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
