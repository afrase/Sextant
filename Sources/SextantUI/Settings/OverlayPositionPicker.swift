import SwiftUI

/// Settings › Keyboard's overlay position (spec §8.4, ADR 0062): a small screen with a menu bar along its top and the
/// nine spots the HUD can take, the chosen one a mini HUD in the accent color and the others hollow. Each spot is a
/// button VoiceOver reads by name, marked selected when it is the chosen one; with the picker focused, the arrow keys
/// move the choice, as in a radio group.
struct OverlayPositionPicker: View {
    @Binding var selection: OverlayPosition
    @Environment(\.isEnabled) private var isEnabled

    private static let size = CGSize(width: 120, height: 76)
    private static let menuBarHeight: CGFloat = 7
    /// Between the screen's edges and the spots against them.
    private static let inset: CGFloat = 5

    var body: some View {
        let screen = RoundedRectangle(cornerRadius: 6, style: .continuous)
        VStack(spacing: 0) {
            Rectangle().fill(.quaternary).frame(height: Self.menuBarHeight)
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(OverlayPosition.allCases.filter { $0.row == row }, id: \.self) { spot($0) }
                    }
                }
            }
            .padding(Self.inset)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(screen.fill(.quaternary.opacity(0.5)))
        .clipShape(screen)
        .overlay(screen.strokeBorder(.separator))
        .opacity(isEnabled ? 1 : 0.5)
        // A screen, not text: left stays left in a right-to-left language.
        .environment(\.layoutDirection, .leftToRight)
        // Focusable with keyboard navigation on, as buttons are: no focus ring the moment Settings opens.
        .focusable(interactions: .activate)
        .onMoveCommand(perform: move)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Position"))
    }

    /// One spot: the whole cell takes the click, and the mini HUD sits against the edges the HUD would.
    private func spot(_ position: OverlayPosition) -> some View {
        let isSelected = position == selection
        return Button {
            selection = position
        } label: {
            hud(isSelected)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Self.alignment(of: position))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The picker takes the focus as a whole, and the arrow keys move the choice.
        .focusable(false)
        .help(position.title)
        .accessibilityLabel(Text(position.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The chosen spot is a mini HUD filled with the accent color; the others are hollow and smaller.
    @ViewBuilder private func hud(_ isSelected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 2.5, style: .continuous)
        if isSelected {
            shape.fill(Color.accentColor).frame(width: 26, height: 14)
        } else {
            shape.strokeBorder(.secondary, lineWidth: 1).frame(width: 16, height: 9)
        }
    }

    private static func alignment(of position: OverlayPosition) -> Alignment {
        switch position {
        case .topLeft: .topLeading
        case .top: .top
        case .topRight: .topTrailing
        case .middleLeft: .leading
        case .center: .center
        case .middleRight: .trailing
        case .bottomLeft: .bottomLeading
        case .bottom: .bottom
        case .bottomRight: .bottomTrailing
        }
    }

    /// The arrow keys move the choice to the next spot that way, and stop at the screen's edges.
    private func move(_ direction: MoveCommandDirection) {
        let (row, column) = (selection.row, selection.column)
        let next: OverlayPosition?
        switch direction {
        case .up: next = OverlayPosition.at(row: row - 1, column: column)
        case .down: next = OverlayPosition.at(row: row + 1, column: column)
        case .left: next = OverlayPosition.at(row: row, column: column - 1)
        case .right: next = OverlayPosition.at(row: row, column: column + 1)
        @unknown default: return
        }
        if let next { selection = next }
    }
}
