import SextantApplication
import SextantDomain
import SwiftUI

/// The macro's steps as caps along a time ruler (spec §6.3). Each wait is a hatched gap that grows with its length,
/// labelled in ms; modifier glyphs sit on the caps. A click selects a step, and the dashed cap adds one.
struct MacroTimeline: View {
    var model: LayoutWindowModel
    var session: EditSession
    var locator: MacroLocator
    var macro: Macro

    private let cap: CGFloat = 44

    /// A wait's gap: room for its label, plus a length that grows with the wait (5 s is about 440 pt).
    private func gap(_ delay: Int) -> CGFloat { delay == 0 ? 6 : 36 + CGFloat(delay) * 0.08 }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 0) {
                        ForEach(Array(macro.steps.enumerated()), id: \.offset) { index, step in
                            stepCap(step, index: index).id(index)
                            wait(step.delay)
                        }
                        if macro.steps.count < Macro.maxSteps {
                            Button {
                                model.openStepPicker(step: nil, in: locator)
                            } label: {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Tokens.ghostStroke.color, style: StrokeStyle(lineWidth: 1, dash: [3, 2.5]))
                                    .frame(width: cap, height: cap)
                                    .overlay { Image(systemName: "plus").font(.callout.weight(.semibold)).foregroundStyle(.secondary) }
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Add Step"))
                        }
                    }
                    .padding(.top, 14)
                    ruler.accessibilityHidden(true)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .scrollIndicators(.never)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onChange(of: session.selection.step) { _, step in
                if let step { withAnimation { proxy.scrollTo(step) } }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Timeline"))
    }

    private func stepCap(_ step: MacroStep, index: Int) -> some View {
        let selected = session.selection.macro == locator && session.selection.step == index
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let tint = Tokens.kind(.macro)?.tint.color ?? .accentColor
        return Button {
            session.selectMacro(locator, step: index)
        } label: {
            CapLegendView(action: Legends.legend(for: KeyAction(code: step.code)), u: cap)
                .foregroundStyle(Tokens.capLegend.color, Tokens.capLegend2.color)
                .frame(width: cap, height: cap)
                .background {
                    shape.fill(LinearGradient(colors: [Tokens.capTop.color, Tokens.capBottom.color], startPoint: .top, endPoint: .bottom))
                    shape.fill(tint.opacity(0.10))
                }
                .overlay { shape.strokeBorder(selected ? Color.accentColor : Tokens.capEdge.color, lineWidth: selected ? 2 : 0.75) }
                .overlay(alignment: .topLeading) {
                    if !step.modifiers.isEmpty {
                        Text(verbatim: step.modifiers.glyphs)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(tint)
                            .padding(.leading, 4)
                            .padding(.top, 2)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    Text(verbatim: "\(index + 1)").font(.system(size: 8, weight: .semibold).monospacedDigit()).foregroundStyle(.tertiary)
                        .padding(.trailing, 4)
                        .padding(.bottom, 2)
                }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(MacroText.spoken(step, index: index))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The pause after a step: a hairline, or a hatched band labelled "150 ms".
    private func wait(_ delay: Int) -> some View {
        ZStack {
            if delay > 0 {
                Hatching(color: .secondary.opacity(0.5))
                    .frame(height: 12)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .padding(.horizontal, 3)
                Text(verbatim: "\(delay) ms")
                    .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .offset(y: -15)
            } else {
                Rectangle().fill(Tokens.capEdge.color).frame(height: 1)
            }
        }
        .frame(width: gap(delay), height: cap)
        .accessibilityHidden(true)
    }

    /// Each step's start time, under it; labels too close to the last one are left out. A key press counts 10 ms.
    private var ruler: some View {
        var marks: [(x: CGFloat, ms: Int)] = []
        var x: CGFloat = 0
        var ms = 0
        for step in macro.steps {
            if marks.last.map({ x - $0.x >= 40 }) ?? true { marks.append((x, ms)) }
            x += cap + gap(step.delay)
            ms += 10 + step.delay
        }
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(Tokens.capEdge.color).frame(width: max(x, 1), height: 1)
            ForEach(Array(marks.enumerated()), id: \.offset) { _, mark in
                VStack(alignment: .leading, spacing: 1) {
                    Rectangle().fill(.tertiary).frame(width: 1, height: 4)
                    Text(verbatim: "\(mark.ms) ms").font(.system(size: 8.5).monospacedDigit()).foregroundStyle(.tertiary).fixedSize()
                }
                .offset(x: mark.x)
            }
        }
        .frame(height: 16, alignment: .topLeading)
    }
}

/// 45° hatching for a wait.
private struct Hatching: View {
    var color: Color

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 4
            }
            context.stroke(path, with: .color(color), lineWidth: 1)
        }
    }
}
