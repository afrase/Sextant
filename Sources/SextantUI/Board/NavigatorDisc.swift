import SextantDomain
import SwiftUI

/// The recessed Navigator disc (spec §4.1). With an `action` it is a button that opens the Navigator popover
/// (ADR 0069); without one (the layer map, exported images) it is drawn only.
struct NavigatorDisc: View {
    var diameter: CGFloat
    var kind: NavigatorConfig.Kind?
    var action: (() -> Void)?
    @State private var isHovered = false

    private var help: String {
        switch kind {
        case .trackball?: String(localized: "Navigator trackball · settings in Firmware Settings › Navigator")
        case .knob?: String(localized: "Navigator knob · settings in Firmware Settings › Navigator")
        default: String(localized: "Navigator trackpad · settings in Firmware Settings › Navigator")
        }
    }

    var body: some View {
        if let action {
            Button(action: action) { disc(highlighted: isHovered) }
                .buttonStyle(.plain)
                .onHover { isHovered = $0 }
                .help(Text("Navigator settings"))
                .accessibilityLabel(Text("Navigator settings"))
        } else {
            disc(highlighted: false).help(help).accessibilityHidden(true)
        }
    }

    private func disc(highlighted: Bool) -> some View {
        Circle()
            .fill(Tokens.ghostFill.color)
            .overlay { Circle().strokeBorder(Tokens.ghostStroke.color, lineWidth: highlighted ? 2 : 1) }
            .overlay {
                Image(systemName: kind == .trackball ? "circle.circle" : "rectangle.and.hand.point.up.left")
                    .font(.system(size: diameter * 0.32))
                    .foregroundStyle(highlighted ? .secondary : .tertiary)
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
    }
}
