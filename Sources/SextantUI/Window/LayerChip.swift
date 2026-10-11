import SextantDomain
import SwiftUI

/// A layer's colour chip: a small rounded square, neutral on layers without a colour (spec §3.6).
struct LayerChip: View {
    var color: HexColor?
    var size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(color.map { LayerTones($0).display.color } ?? Tokens.neutralChip.color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
