import SextantApplication
import SextantDomain
import SwiftUI

/// The four slot tabs (spec §5.1): each shows its title and what it holds, or `plus` when empty.
struct SlotStrip: View {
    var session: EditSession
    var key: Key
    var index: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(KeySlot.allCases) { slot in
                let legend = key[slot].filledAction.map { Legends.legend(for: $0, layerNames: session.layout.layerNames) }
                let mini = legend.map { $0.layerName ?? CapLegendView.capText(for: $0) }
                let selected = session.selection.slot == slot
                let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
                Button {
                    session.select(key: index, slot: slot)
                } label: {
                    VStack(spacing: 4) {
                        Text(slot.title)
                            .font(.caption)
                            .foregroundStyle(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                        if let mini {
                            Text(verbatim: mini).font(.callout.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                        } else {
                            Image(systemName: "plus").foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(shape.fill(.quaternary.opacity(0.5)))
                    .overlay { if selected { shape.strokeBorder(Color.accentColor, lineWidth: 1.5) } }
                    .contentShape(shape)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "\(slot.title): \(legend?.name ?? String(localized: "empty"))"))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        // Every tab as tall as the tallest.
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isTabBar)
        .accessibilityLabel(Text("Slots"))
    }
}

/// The editor for the selected slot (spec §5.2, §5.3). Tap and Double tap pick a keycode and its chord; Hold and
/// Tap then hold choose a modifier, a layer, a key or nothing.
struct SlotEditor: View {
    var model: LayoutWindowModel
    var session: EditSession
    var slot: KeySlot
    /// The slot's action; nil when empty (a transparent tap counts as empty).
    var action: KeyAction?
    /// The layer the key is on.
    var layer: Int

    var body: some View {
        switch slot {
        case .tap, .doubleTap: tapEditor
        case .hold, .tapHold: holdEditor
        }
    }

    // MARK: Tap and Double tap

    @ViewBuilder private var tapEditor: some View {
        if let action {
            keycodeRow(action)
            if KeycodeCatalog.layerFunctions.contains(action.canonicalCode) {
                LayerRows(session: session, slot: slot, action: action, layer: layer, showsBehaviour: true)
            }
            // A chord means nothing on a macro, a colour key or a layer key (LM's modifiers excepted).
            if action.macro == nil, action.color == nil, !action.isLayerAction || action.canonicalCode == "LM" {
                LabeledContent("Chord") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach([false, true], id: \.self) { right in
                            HStack(spacing: 4) {
                                Text(verbatim: right ? "R" : "L").font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(
                                    width: 10)
                                ForEach(Modifiers.columns, id: \.glyph) { column in
                                    modifierToggle(
                                        right ? column.right : column.left, glyph: column.glyph, in: action.modifiers, set: setChord)
                                }
                            }
                        }
                        hyperAndMeh(action.modifiers, set: setChord)
                    }
                    .toggleStyle(.button)
                }
            }
        } else {
            emptyTile(
                slot == .tap ? String(localized: "Add tap") : String(localized: "Add double tap"),
                hint: slot == .tap
                    ? String(localized: "Send a key when tapped") : String(localized: "Tap twice quickly to send another key"))
        }
    }

    private func setChord(_ modifiers: Modifiers) { session.setChord(modifiers, slot: slot) }

    // MARK: Hold and Tap then hold

    @ViewBuilder private var holdEditor: some View {
        let mode = HoldMode(action)
        Picker("Holding", selection: Binding(get: { mode }, set: { setMode($0, from: mode) })) {
            ForEach(HoldMode.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        // Small, as the lens picker. The frame keeps its width from widening the inspector and moving the board.
        // shortcut: the four equal segments are ~6 pt wider than 248 pt and overhang the padding by ~3 pt a side; mini
        // fits but its 9 pt labels are hard to read.
        .controlSize(.small)
        .frame(minWidth: 0, maxWidth: .infinity)
        switch (mode, action) {
        case let (.modifier, action?):
            let held = action.heldModifiers
            let right = held.isRightSided
            LabeledContent("Modifiers") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        ForEach(Modifiers.columns, id: \.glyph) { column in
                            modifierToggle(right ? column.right : column.left, glyph: column.glyph, in: held, set: setHeld)
                        }
                    }
                    hyperAndMeh(held, set: setHeld)
                }
                .toggleStyle(.button)
            }
            LabeledContent("Side") {
                Picker("Side", selection: Binding(get: { right }, set: { setHeld(held.onSide(right: $0)) })) {
                    Text("Left").tag(false)
                    Text("Right").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        case let (.layer, action?):
            LayerRows(session: session, slot: slot, action: action, layer: layer, showsBehaviour: false)
        case let (.key, action?):
            keycodeRow(action)
        default:
            Text(
                slot == .hold
                    ? String(localized: "Hold for a modifier or a layer.") : String(localized: "Tap, then hold, for a modifier or a layer.")
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private func setMode(_ mode: HoldMode, from current: HoldMode) {
        guard mode != current else { return }
        switch mode {
        case .modifier: setHeld(.leftControl)
        case .layer:
            // A layer above this one: a lower one held from here stays hidden under it.
            let layers = session.layout.layers.indices
            session.setAction(.momentary(layers.first { $0 > layer } ?? layers.first { $0 != layer } ?? layer), slot: slot)
        // The picker assigns the key to this slot.
        case .key: model.openKeycodePicker()
        case .nothing: session.setAction(nil, slot: slot)
        }
    }

    /// No modifiers left means nothing held.
    private func setHeld(_ modifiers: Modifiers) { session.setAction(.holding(modifiers), slot: slot) }

    // MARK: Parts

    /// The action tile with Change… and Clear (spec §5.2). The tile and Change… open the keycode picker.
    private func keycodeRow(_ action: KeyAction) -> some View {
        let legend = Legends.legend(for: action, layerNames: session.layout.layerNames)
        return LabeledContent("Keycode") {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    model.openKeycodePicker()
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
                .accessibilityLabel(String(localized: "Keycode: \(legend.name), \(legend.qmk)"))
                .accessibilityHint(Text("Opens the keycode picker."))
                HStack {
                    Button("Change…") { model.openKeycodePicker() }
                    Button("Clear") { session.setAction(nil, slot: slot) }
                }
            }
        }
    }

    /// A dashed tile for an empty slot; clicking it opens the keycode picker.
    private func emptyTile(_ title: String, hint: String) -> some View {
        Button {
            model.openKeycodePicker()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: "plus")
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Tokens.ghostStroke.color, style: StrokeStyle(lineWidth: 1, dash: [3, 2.5]))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Opens the keycode picker."))
    }

    private func modifierToggle(_ modifier: Modifiers, glyph: String, in modifiers: Modifiers, set: @escaping (Modifiers) -> Void)
        -> some View
    {
        Toggle(isOn: Binding(get: { modifiers.contains(modifier) }, set: { _ in set(modifiers.symmetricDifference(modifier)) })) {
            Text(verbatim: glyph).frame(minWidth: 14)
        }
        .accessibilityLabel(modifier.names.joined())
    }

    private func hyperAndMeh(_ modifiers: Modifiers, set: @escaping (Modifiers) -> Void) -> some View {
        HStack(spacing: 4) {
            Toggle("Hyper", isOn: Binding(get: { modifiers == .hyper }, set: { set($0 ? .hyper : []) }))
            Toggle("Meh", isOn: Binding(get: { modifiers == .meh }, set: { set($0 ? .meh : []) }))
        }
    }
}

/// A layer action's behaviour and target (spec §5.3), with a warning when the target can't work from here.
private struct LayerRows: View {
    var session: EditSession
    var slot: KeySlot
    var action: KeyAction
    var layer: Int
    var showsBehaviour: Bool

    var body: some View {
        let code = action.canonicalCode
        if showsBehaviour {
            LabeledContent("Behavior") {
                Picker("Behavior", selection: Binding(get: { code }, set: { update(code: $0) })) {
                    ForEach(KeyText.layerBehaviours(current: code), id: \.code) { Text($0.title).tag($0.code) }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
        LabeledContent("Layer") {
            Picker("Layer", selection: Binding(get: { action.layer ?? -1 }, set: { update(layer: $0) })) {
                ForEach(Array(session.layout.layers.enumerated()), id: \.offset) { index, item in
                    Text(index == layer ? String(localized: "\(index) · \(item.title) (this layer)") : "\(index) · \(item.title)").tag(
                        index)
                }
            }
            .labelsHidden()
        }
        if let target = action.layer, let warning = KeyText.layerWarning(code: code, target: target, own: layer, layout: session.layout) {
            Label {
                Text(warning)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Tokens.warning.color)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private func update(code: String? = nil, layer target: Int? = nil) {
        var next = action
        if let code {
            next.code = code
            if code != "LM" { next.modifiers = [] }
        }
        if let target { next.layer = target }
        session.setAction(next, slot: slot)
    }
}

extension Optional where Wrapped == KeyAction {
    /// The action, unless it's missing or transparent: what a slot shows as filled.
    var filledAction: KeyAction? { self.flatMap { $0.isTransparent ? nil : $0 } }
}

/// Inspector rows (spec §3.8): an 84 pt right-aligned label column, then the control.
struct InspectorRowStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.label.foregroundStyle(.secondary).frame(width: 84, alignment: .trailing)
            configuration.content.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
