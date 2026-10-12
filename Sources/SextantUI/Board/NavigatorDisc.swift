import SextantDomain
import SwiftUI

/// The recessed, non-interactive Navigator disc (spec §4.1).
struct NavigatorDisc: View {
    var diameter: CGFloat
    var kind: NavigatorConfig.Kind?

    private var help: String {
        switch kind {
        case .trackball?: String(localized: "Navigator trackball · settings in Firmware Settings › Navigator")
        case .knob?: String(localized: "Navigator knob · settings in Firmware Settings › Navigator")
        default: String(localized: "Navigator trackpad · settings in Firmware Settings › Navigator")
        }
    }

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
            .help(help)
            .accessibilityHidden(true)
    }
}
