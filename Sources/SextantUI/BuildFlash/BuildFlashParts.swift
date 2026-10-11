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

/// Card A, the reset button, and card B, the Reset key, each on a small drawing of the user's own board (spec §7.3).
struct FlashModeCards: View {
    var layout: KeyboardLayout
    var geometry: BoardGeometry

    var body: some View {
        let place = KeyText.resetButtonPlace(layout: layout, geometry: geometry)
        HStack(alignment: .top, spacing: 12) {
            card(String(localized: "Use the reset button")) {
                MiniBoard(geometry: geometry, layout: layout, button: (layout.board ?? .voyager).resetButtonKey)
                    .accessibilityLabel(String(localized: "Keyboard drawing with the reset button marked \(place)"))
                Text("Press the reset button \(place).").fixedSize(horizontal: false, vertical: true)
            }
            if let path = FlashPath.find(in: layout) {
                let keys = path.holds.map { ($0, true) } + [(path.reset, false)]
                let steps = keys.map { KeyText.flashStep($0, isHold: $1, layout: layout, geometry: geometry) }
                let marks = Dictionary(keys.enumerated().map { ($1.0.index, $0 + 1) }) { first, _ in first }
                let spoken = steps.enumerated().map { "\($0 + 1): \($1.position)" }.joined(separator: "; ")
                card(String(localized: "Or use your Reset key")) {
                    MiniBoard(geometry: geometry, layout: layout, marks: marks)
                        .accessibilityLabel(String(localized: "Keyboard drawing with the keys to press numbered. \(spoken)"))
                    ForEach(steps.indices, id: \.self) { n in step(n + 1, steps[n]) }
                }
            } else {
                card(nil) {
                    Label("Add a Reset key (QK_BOOT) to a layer to enter flash mode from the keyboard.", systemImage: "info.circle")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)  // both cards as tall as the taller one
        .font(.callout)
    }

    private func card(_ title: String?, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { Text(title).font(.headline).accessibilityAddTraits(.isHeader) }
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
    }

    private func step(_ number: Int, _ step: (text: String, position: String)) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: "\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.accentColor))
            VStack(alignment: .leading, spacing: 1) {
                Text(step.text)
                Text(step.position).font(.caption).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A small top-down drawing of the board from its own key shapes (no product art): the case follows the keys, `marks`
/// numbers keys, and `button` marks the reset button on the case's top edge above that key.
private struct MiniBoard: View {
    var geometry: BoardGeometry
    var layout: KeyboardLayout
    var marks: [Int: Int] = [:]
    var button: Int?
    @Environment(\.colorScheme) private var colorScheme

    /// Margin around the keys in key units: room for the button's halo.
    private static let margin = 0.8

    var body: some View {
        let bounds = geometry.bounds
        GeometryReader { proxy in
            let pitch = proxy.size.width / (bounds.width + 2 * Self.margin)
            let spacing = pitch * 0.16
            let board = geometry.layout(keySize: pitch - spacing, spacing: spacing, padding: pitch * Self.margin + spacing / 2)
            let rim = pitch * 0.2
            ZStack(alignment: .topLeading) {
                // One opaque shape per key, plus a bridge to each thumb cluster, faded as a group so overlaps don't show.
                ZStack(alignment: .topLeading) {
                    BoardCanvas(layout: board) { _ in RoundedRectangle(cornerRadius: rim * 1.5, style: .continuous).padding(-rim) }
                    ForEach(bridges(board), id: \.minX) { bridge in
                        Rectangle().frame(width: bridge.width, height: bridge.height).position(x: bridge.midX, y: bridge.midY)
                    }
                }
                .foregroundStyle(colorScheme == .dark ? Color.black : Color.primary)
                .compositingGroup()
                .opacity(colorScheme == .dark ? 0.5 : 0.13)
                // Under the keys, so the halo shows above the edge and the key keeps its legend.
                if let button, board.frames.indices.contains(button) {
                    let frame = board.frame(button)
                    ResetButtonMarker(pitch: pitch).position(x: frame.center.x, y: frame.boundingBox.minY - rim)
                }
                BoardCanvas(layout: board) { frame in key(frame, pitch: pitch) }
            }
        }
        .aspectRatio((bounds.width + 2 * Self.margin) / (bounds.height + 2 * Self.margin), contentMode: .fit)
        .accessibilityElement(children: .ignore)
    }

    /// Per half, the case between the main keys and the thumb cluster: under the columns the thumbs sit beneath, from
    /// the bottom row down to the thumbs' middle.
    private func bridges(_ board: BoardLayout) -> [CGRect] {
        BoardGeometry.Hand.allCases.compactMap { hand in
            func box(_ cluster: BoardGeometry.Cluster) -> CGRect {
                board.frames.filter { $0.hand == hand && geometry.keys[safe: $0.index]?.cluster == cluster }.map(\.boundingBox)
                    .reduce(CGRect.null) { $0.union($1) }
            }
            let main = box(.main), thumbs = box(.thumb)
            guard !main.isNull, !thumbs.isNull else { return nil }
            let minX = max(main.minX, thumbs.minX), maxX = min(main.maxX, thumbs.maxX)
            let top = main.maxY - board.pitch / 2
            guard maxX > minX, thumbs.midY > top else { return nil }
            return CGRect(x: minX, y: top, width: maxX - minX, height: thumbs.midY - top)
        }
    }

    @ViewBuilder private func key(_ frame: BoardLayout.KeyFrame, pitch: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: pitch * 0.14, style: .continuous)
        if let number = marks[frame.index] {
            shape.fill(Color.accentColor)
                .overlay {
                    Text(verbatim: "\(number)").font(.system(size: pitch * 0.5, weight: .bold)).foregroundStyle(.white)
                        .rotationEffect(.degrees(-frame.rotation))
                }
        } else {
            shape.fill(Tokens.capTop.color)
                .overlay { shape.strokeBorder(Tokens.capEdge.color, lineWidth: 0.5) }
                .overlay {
                    // The key under the button shows its legend, so "above the 3 key" has a 3 to find.
                    if frame.index == button, let name = KeyText.baseName(layout: layout, index: frame.index) {
                        Text(name).font(.system(size: pitch * 0.55, weight: .semibold))
                            .foregroundStyle(Tokens.capLegend.color).minimumScaleFactor(0.5).lineLimit(1)
                    }
                }
        }
    }
}

/// The reset button on the case edge: an accent pill in a ring, with a halo that pulses outward (held still under
/// Reduce Motion, and in snapshots so renders match).
private struct ResetButtonMarker: View {
    var pitch: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        ZStack {
            if reduceMotion || isSnapshot {
                halo(0.35)
            } else {
                TimelineView(.animation) { context in
                    // One pulse every 1.6 s.
                    halo(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6)
                }
            }
            Circle().strokeBorder(Color.accentColor, lineWidth: 1.5).frame(width: pitch * 1.1, height: pitch * 1.1)
            Capsule().fill(Color.accentColor).frame(width: pitch * 0.7, height: pitch * 0.3)
        }
        .frame(width: pitch * 1.8, height: pitch * 1.8)
    }

    private func halo(_ phase: Double) -> some View {
        Circle().fill(Color.accentColor.opacity(0.4 * (1 - phase))).frame(
            width: pitch * (1.1 + 0.7 * phase), height: pitch * (1.1 + 0.7 * phase))
    }
}
