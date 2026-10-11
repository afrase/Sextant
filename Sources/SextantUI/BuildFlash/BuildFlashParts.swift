import SextantDomain
import SwiftUI

/// Five nodes, Build · Flash mode · Write · Verify · Done, each with an optional sublabel (spec §7.2).
struct StepIndicator: View {
    var step: Int
    /// The current step finished (a build without flashing, or the end).
    var isStepDone: Bool
    var failed: Bool
    var sublabels: [String?]

    private static let titles = [
        String(localized: "Build"), String(localized: "Flash mode"), String(localized: "Write"), String(localized: "Verify"),
        String(localized: "Done"),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Self.titles.indices, id: \.self) { index in
                let number = index + 1
                VStack(spacing: 4) {
                    ZStack {
                        Circle().fill(.background)  // hides the line behind the node
                        Circle().strokeBorder(number <= step ? tint(number) : Color.secondary.opacity(0.4), lineWidth: 1.5)
                        if number < step || (number == step && isStepDone) {
                            Circle().fill(Color.accentColor)
                            Image(systemName: "checkmark").font(.caption2.weight(.bold)).foregroundStyle(.white)
                        } else if number == step && failed {
                            Image(systemName: "xmark").font(.caption2.weight(.bold)).foregroundStyle(Tokens.danger.color)
                        } else {
                            Text(verbatim: "\(number)").font(.caption2.weight(.semibold)).foregroundStyle(
                                number == step ? .primary : .secondary)
                        }
                    }
                    .frame(width: 20, height: 20)
                    Text(Self.titles[index]).font(.caption).foregroundStyle(number == step ? .primary : .secondary)
                    Text(verbatim: sublabels[safe: index].flatMap { $0 } ?? " ").font(.caption2.monospacedDigit()).foregroundStyle(
                        .secondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(number == step ? .isSelected : [])
            }
        }
        .background(alignment: .top) {
            // The line behind the nodes, from the first centre to the last.
            GeometryReader { proxy in
                Rectangle().fill(Color.secondary.opacity(0.25)).frame(width: proxy.size.width * 0.8, height: 1)
                    .offset(x: proxy.size.width * 0.1, y: 10)
            }
        }
    }

    private func tint(_ number: Int) -> Color { number == step && failed ? Tokens.danger.color : .accentColor }
}

/// Bytes used against the board's application flash, one bar in the accent colour, red when over (spec §7.3).
struct SizeMeter: View {
    var used: Int
    var capacity: Int

    var body: some View {
        let over = used > capacity
        let fraction = capacity > 0 ? min(Double(used) / Double(capacity), 1) : 1
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule().fill(over ? Tokens.danger.color : Color.accentColor).frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 8)
            HStack {
                Text("\(used.formatted()) of \(capacity.formatted()) bytes · \(Int((fraction * 100).rounded()))%")
                Spacer()
                if over {
                    Text("\((used - capacity).formatted()) bytes over").foregroundStyle(Tokens.danger.color)
                } else {
                    Text("\((capacity - used).formatted()) bytes free")
                }
            }
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The signature flash ring (spec §7.3): a graduated bezel, a tick every 3.6° and a major one every 36°, the phase's
/// progress in the accent colour, and the phase percentage with its name in the centre.
struct SextantRing: View {
    var fraction: Double?
    var label: String
    var showsPercent: Bool

    var body: some View {
        ZStack {
            Canvas { context, size in
                let radius = min(size.width, size.height) / 2
                let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                for tick in 0..<100 {
                    let major = tick.isMultiple(of: 10)
                    let angle = Double(tick) * 3.6 * .pi / 180
                    let direction = CGPoint(x: sin(angle), y: -cos(angle))
                    var path = Path()
                    path.move(
                        to: CGPoint(
                            x: centre.x + direction.x * (radius - (major ? 11 : 6)), y: centre.y + direction.y * (radius - (major ? 11 : 6))
                        ))
                    path.addLine(to: CGPoint(x: centre.x + direction.x * radius, y: centre.y + direction.y * radius))
                    context.stroke(path, with: .color(.secondary.opacity(major ? 0.8 : 0.35)), lineWidth: major ? 1.5 : 1)
                }
            }
            Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 6).padding(19)
            Circle()
                .trim(from: 0, to: fraction ?? 0)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(19)
                .animation(.linear(duration: 0.25), value: fraction)
            VStack(spacing: 0) {
                if showsPercent, let fraction {
                    Text(verbatim: "\(Int((fraction * 100).rounded()))%").font(.system(size: 40, weight: .semibold).monospacedDigit())
                }
                Text(label).font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(width: 168, height: 168)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(showsPercent ? fraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "" : "")
    }
}

/// Card A, the reset button, and card B, the Reset key on the user's own board (spec §7.3).
struct FlashModeCards: View {
    var layout: KeyboardLayout?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            card {
                Image(systemName: "button.horizontal.top.press").font(.largeTitle).foregroundStyle(.tint).accessibilityHidden(true)
                Text("Press the small reset button on the left half once.")
            }
            card {
                if let layout, let path = FlashPath.find(in: layout) {
                    ForEach(Array(path.holds.enumerated()), id: \.offset) { n, hold in
                        let target = (n + 1 < path.holds.count ? path.holds[n + 1].layer : path.reset.layer)
                        step(n + 1, key: hold, in: layout, text: holdText(hold, target: target, in: layout))
                    }
                    step(
                        path.holds.count + 1, key: path.reset, in: layout, text: String(localized: "Press Reset (key \(path.reset.index))"))
                } else {
                    Label("Add a Reset key (QK_BOOT) to a layer to enter flash mode from the keyboard.", systemImage: "info.circle")
                }
            }
        }
        .font(.callout)
    }

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
    }

    private func step(_ number: Int, key: KeyRef, in layout: KeyboardLayout, text: String) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: "\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.accentColor))
            KeyCap(model: KeyCapModel(layout: layout, layer: key.layer, index: key.index), u: 32).frame(width: 32, height: 32)
                .accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// "Hold Space (key 51), which keeps Brd+Sys active".
    private func holdText(_ hold: KeyRef, target: Int, in layout: KeyboardLayout) -> String {
        let primary = Legends.legend(layout: layout, layer: hold.layer, index: hold.index).legend.primary
        let name = primary.flatMap { $0.layer == nil ? $0.name : nil } ?? String(localized: "the key")
        let layer = layout.layers[safe: target]?.title ?? String(localized: "Layer \(target)")
        return String(localized: "Hold \(name) (key \(hold.index)), which keeps \(layer) active")
    }
}
