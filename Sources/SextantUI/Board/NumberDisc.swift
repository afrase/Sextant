import SwiftUI

/// A number in white on a filled circle, like the "3.circle.fill" symbols but legible with two or three digits: a combo's
/// number on a cap and on its card.
struct NumberDisc: View {
    var text: String
    var color: Token
    var diameter: CGFloat

    var body: some View {
        Circle().fill(color.color)
            .overlay {
                Text(verbatim: text)
                    .font(.system(size: diameter * 0.56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .tracking(-0.3)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.horizontal, 1)
                    .foregroundStyle(.white)
            }
            .frame(width: diameter, height: diameter)
    }
}

/// A cap's corner badge, drawn like the issue badge: white shows through a filled symbol's cut-out ("plus.circle.fill",
/// "3.circle.fill"). The Combos overlay draws more of them beside a cap's own.
struct MarkBadge: View {
    var mark: CapDecoration.Mark

    var body: some View {
        if let text = mark.text {
            NumberDisc(text: text, color: mark.color, diameter: 14)
        } else {
            Image(systemName: mark.symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(mark.color.color)
                .background { Circle().fill(.white).padding(1) }
                .frame(width: 14, height: 14)
        }
    }
}
