import SextantApplication
import SextantDomain
import SwiftUI

/// The empty window's Welcome (spec §12.1): the mark, then three ways in. No tours; the cards say what each does.
struct WelcomeView: View {
    var model: LayoutWindowModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 24) {
            SextantMark()
                .stroke(.tertiary, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .frame(width: 88, height: 88)
                .accessibilityHidden(true)
            Text("Bring your layout to Sextant").font(.title2.weight(.semibold))
            HStack(alignment: .top, spacing: 12) {
                WelcomeCard(
                    title: "Import from your Voyager", systemImage: "keyboard",
                    detail: "Reads the layout ID from the keyboard and downloads it from Oryx, read-only."
                ) { model.openImport(model.connectedOryxSerial) }
                .disabled(!model.canImport || model.connectedOryxSerial == nil)
                WelcomeCard(
                    title: "Paste an Oryx link", systemImage: "link",
                    detail: "Imports a public layout from configure.zsa.io. Oryx stays read-only; Sextant keeps its own copy."
                ) { model.openImport() }
                .disabled(!model.canImport)
                WelcomeCard(
                    title: "Start from a blank QWERTY layout", systemImage: "plus.square",
                    detail: "One layer, authored by Sextant, ready to build on."
                ) { Task { await addBlankLayout(to: model.library, from: model, openWindow: openWindow) } }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct WelcomeCard: View {
    var title: LocalizedStringKey
    var systemImage: String
    var detail: LocalizedStringKey
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: systemImage).font(.title2).foregroundStyle(.tint).frame(height: 28).accessibilityHidden(true)
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            .padding(16)
            // Three fit the 640 pt centre column with the page's 32 pt margins.
            .frame(width: 184, alignment: .topLeading)
            .frame(minHeight: 176, alignment: .top)
        }
        .buttonStyle(CardButtonStyle())
    }
}

/// A flat card on the window background: no glass on pages (spec §10.4); radius 10 (§10.3).
private struct CardButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(configuration.isPressed ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.quinary))
            )
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
    }
}

/// The sextant mark (spec §10.7): a 60° graduated arc with seven ticks, hung from a pivot, and an index arm.
struct SextantMark: Shape {
    func path(in rect: CGRect) -> Path {
        let pivot = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.08)
        let radius = rect.height * 0.86
        func point(_ degrees: Double, _ r: CGFloat) -> CGPoint {
            let a = Angle.degrees(degrees).radians
            return CGPoint(x: pivot.x + cos(a) * r, y: pivot.y + sin(a) * r)
        }
        var path = Path()
        path.addArc(center: pivot, radius: radius, startAngle: .degrees(60), endAngle: .degrees(120), clockwise: false)
        for degrees in [60.0, 120.0] {
            path.move(to: pivot)
            path.addLine(to: point(degrees, radius))
        }
        for tick in 0..<7 {
            let degrees = 60 + Double(tick) * 10
            path.move(to: point(degrees, radius * (tick.isMultiple(of: 3) ? 0.82 : 0.9)))
            path.addLine(to: point(degrees, radius))
        }
        path.move(to: pivot)
        path.addLine(to: point(78, radius * 0.97))
        return path
    }
}
