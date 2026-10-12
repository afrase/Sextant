extension LayoutWindowModel {
    /// How the window's board mode marks a cap (ADR 0037). Changes, Combos and Heatmap each add one case here and
    /// build their decoration in their own files, so none of them edits BoardView or KeyCap.
    func capDecoration(layer: Int, index: Int) -> CapDecoration {
        switch page {
        case .history: history?.decoration(layer: layer, index: index) ?? CapDecoration()
        default: CapDecoration()
        }
    }
}
