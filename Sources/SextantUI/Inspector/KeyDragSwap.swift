import AppKit
import SextantApplication
import SextantDomain
import SwiftUI

extension View {
    /// Drag a cap onto another to swap them, or ⌥-drag to copy (spec §5.5), each one undo step. A gesture on the whole
    /// board rather than system drag and drop (ADR 0027): it can't leave the window, and it needs no AppKit drop view,
    /// which `ImageRenderer` snapshots draw as a placeholder.
    func keySwapGesture(_ session: EditSession, board: BoardLayout) -> some View {
        modifier(KeySwapGesture(session: session, board: board))
    }
}

private struct KeySwapGesture: ViewModifier {
    var session: EditSession
    var board: BoardLayout
    @State private var drag: (from: CGPoint, to: CGPoint)?

    func body(content: Content) -> some View {
        content
            // Simultaneous, so a click still selects; a drag only starts once the pointer moves.
            .simultaneousGesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { drag = ($0.startLocation, $0.location) }
                    .onEnded { value in
                        drag = nil
                        // Reading the modifier state at the drop needs no event monitor.
                        let copy = NSEvent.modifierFlags.contains(.option)
                        session.dragKey(from: value.startLocation, to: value.location, on: board, copy: copy)
                    }
            )
            .overlay(alignment: .topLeading) {
                if let drag, let source = board.keyIndex(at: drag.from).map(board.frame) {
                    guide(from: source, to: board.keyIndex(at: drag.to).map(board.frame), pointer: drag.to)
                }
            }
    }

    /// A dashed line from the dragged cap, and an accent outline on the cap it would land on (spec §4.7).
    @ViewBuilder private func guide(from source: BoardLayout.KeyFrame, to target: BoardLayout.KeyFrame?, pointer: CGPoint) -> some View {
        Path { path in
            path.move(to: source.center)
            path.addLine(to: target?.center ?? pointer)
        }
        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        .allowsHitTesting(false)
        if let target, target.index != source.index {
            RoundedRectangle(cornerRadius: 0.16 * board.keySize, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .frame(width: target.size.width, height: target.size.height)
                .rotationEffect(.degrees(target.rotation))
                .position(target.center)
                .allowsHitTesting(false)
        }
    }
}

extension EditSession {
    /// Swaps the key under `start` with the key under `end` on the shown layer, or copies it there, and selects where it
    /// landed. False when either point misses a key or both hit the same one.
    @discardableResult
    func dragKey(from start: CGPoint, to end: CGPoint, on board: BoardLayout, copy: Bool) -> Bool {
        guard let source = board.keyIndex(at: start), let target = board.keyIndex(at: end), source != target else { return false }
        swapKeys(source, target, copy: copy)
        select(key: target)
        return true
    }
}
