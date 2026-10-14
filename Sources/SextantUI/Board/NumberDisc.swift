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
