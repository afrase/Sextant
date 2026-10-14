import Foundation

extension BoardGeometry {
    /// Key indices as VoiceOver reads the board (spec §4.11): the left half row by row, its thumbs, then the right half
    /// and its thumbs. A ⇧-click range and the picker's ⌘⏎ follow it too.
    public var readingOrder: [Int] {
        keys.sorted {
            ($0.hand == .right ? 1 : 0, $0.cluster == .thumb ? 1 : 0, $0.row, $0.center.x)
                < ($1.hand == .right ? 1 : 0, $1.cluster == .thumb ? 1 : 0, $1.row, $1.center.x)
        }
        .map(\.index)
    }

    /// The keys from `anchor` to `index` in ``readingOrder``, both included; `[index]` when either is off the board.
    public func range(from anchor: Int, to index: Int) -> [Int] {
        let order = readingOrder
        guard let a = order.firstIndex(of: anchor), let b = order.firstIndex(of: index) else { return [index] }
        return Array(order[min(a, b)...max(a, b)])
    }
}
