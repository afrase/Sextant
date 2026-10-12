import SextantApplication
import SextantDomain
import SwiftUI

/// The step inspector (spec §6.3): the key tile (it opens the picker, limited to keys a step can type), the modifiers,
/// the wait after the step, Duplicate and Delete. Every change is one undo step.
struct MacroStepInspector: View {
    var model: LayoutWindowModel
    var session: EditSession

    var body: some View {
        if let locator = session.selection.macro, let macro = session.layout.macro(at: locator), let index = session.selection.step,
            let step = macro.steps[safe: index]
        {
            VStack(alignment: .leading, spacing: 12) {
                Text("Step \(index + 1) of \(macro.steps.count)").font(.headline)
                if !MacroStep.canType(step.code) {
                    Label {
                        Text("A macro can’t type \(step.code). Choose another key.")
                    } icon: {
                        Image(systemName: "xmark.octagon.fill").foregroundStyle(Tokens.danger.color)
                    }
                    .font(.callout)
                }
                LabeledContent("Key") { keyTile(step, index: index, in: locator) }
                LabeledContent("Modifiers") { modifierGrid(step, index: index, in: locator) }
                LabeledContent("Then wait") {
                    WaitControl(stored: step.delay) { session.setStepDelay($0, at: index, in: locator) }.id("\(locator)/\(index)")
                }
                Divider()
                HStack {
                    Button {
                        session.duplicateStep(at: index, in: locator)
                    } label: {
                        Text("Duplicate").frame(maxWidth: .infinity)
                    }
                    .disabled(macro.steps.count >= Macro.maxSteps)
                    Button {
                        session.deleteStep(at: index, in: locator)
                    } label: {
                        Text("Delete").frame(maxWidth: .infinity)
                    }
                }
            }
            .labeledContentStyle(InspectorRowStyle())
        } else {
            Text("Select a step").foregroundStyle(.secondary)
        }
    }

    /// Left and right ⌃ ⌥ ⇧ ⌘ toggles for the step's modifiers.
    private func modifierGrid(_ step: MacroStep, index: Int, in locator: MacroLocator) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach([false, true], id: \.self) { right in
                HStack(spacing: 4) {
                    Text(verbatim: right ? "R" : "L").font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(width: 10)
                    ForEach(Modifiers.columns, id: \.glyph) { column in
                        let modifier = right ? column.right : column.left
                        Toggle(
                            isOn: Binding(
                                get: { step.modifiers.contains(modifier) },
                                set: { _ in session.setStepModifiers(step.modifiers.symmetricDifference(modifier), at: index, in: locator) }
                            )
                        ) {
                            Text(verbatim: column.glyph).frame(minWidth: 14)
                        }
                        .accessibilityLabel(modifier.names.joined())
                    }
                }
            }
        }
        .toggleStyle(.button)
    }

    /// The step's key as a tile; it and its magnifier open the picker.
    private func keyTile(_ step: MacroStep, index: Int, in locator: MacroLocator) -> some View {
        let legend = Legends.legend(for: KeyAction(code: step.code))
        return Button {
            model.openStepPicker(step: index, in: locator)
        } label: {
            HStack(spacing: 8) {
                CapLegendView(action: legend, u: 32)
                    .frame(width: 32, height: 32)
                    .foregroundStyle(Tokens.capLegend.color, Tokens.capLegend2.color)
                    .background {
                        RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Tokens.capTop.color)
                            .stroke(Tokens.capEdge.color, lineWidth: 0.75)
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: legend.name).lineLimit(1)
                    Text(verbatim: legend.qmk).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .frame(height: 44)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Key: \(legend.name), \(legend.qmk)"))
        .accessibilityHint(Text("Opens the keycode picker."))
    }
}

/// "Then wait": a slider and a field, 0–5000 ms. A drag is one undo step, committed when it ends.
private struct WaitControl: View {
    var stored: Int
    var commit: (Int) -> Void
    @State private var dragged: Int?
    @State private var isDragging = false

    var body: some View {
        HStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { Self.position(dragged ?? stored) },
                    // Keyboard and VoiceOver steps come without a drag: each commits.
                    set: { if isDragging { dragged = Self.milliseconds($0) } else { commit(Self.milliseconds($0)) } })
            ) { editing in
                isDragging = editing
                if !editing, let value = dragged {
                    dragged = nil
                    commit(value)
                }
            }
            .controlSize(.small)
            .accessibilityLabel(Text("Wait after this step"))
            .accessibilityValue(Text("\(dragged ?? stored) ms"))
            TextField("Wait", value: Binding(get: { dragged ?? stored }, set: { commit($0) }), format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 48)
                .accessibilityLabel(Text("Wait in milliseconds"))
            Text("ms").foregroundStyle(.secondary)
        }
    }

    /// The slider runs on a square-root scale, so the short waits most macros use get most of its track; it lands on
    /// whole 10 ms.
    private static func position(_ ms: Int) -> Double { (Double(ms) / Double(Macro.maxDelay)).squareRoot() }
    private static func milliseconds(_ position: Double) -> Int { Int((position * position * Double(Macro.maxDelay) / 10).rounded()) * 10 }
}
