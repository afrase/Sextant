import SextantApplication
import SextantDomain
import SwiftUI

/// The combo editor (spec §6.4, §3.8): name, trigger keys as removable chips, the output tile, the layer the keys come
/// from, the combo window, and the combo's warnings. Every change is one undo step.
struct ComboInspector: View {
    var model: LayoutWindowModel
    var session: EditSession

    var body: some View {
        if let draft = model.combos.draft, let item = model.draftCombo {
            draftView(draft, item)
        } else if let item = model.selectedPageCombo {
            editor(item)
        } else {
            Text("Select a combo or press N to make one").foregroundStyle(.secondary)
            Button("New Combo") { model.startNewCombo() }
        }
    }

    // MARK: Choosing keys

    private func draftView(_ draft: ComboDraft, _ item: NumberedCombo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ComboNumber(item: item)
                Text(draft.combo == nil ? String(localized: "New Combo") : ComboText.title(item.combo, number: item.number))
                    .font(.title3.weight(.semibold))
            }
            Text(
                draft.combo == nil
                    ? String(localized: "Click 2–6 keys on the board, then choose what they send together.")
                    : String(localized: "Click keys on the board to add them or take them out.")
            )
            .font(.callout).foregroundStyle(.secondary)
            LabeledContent("Keys") {
                Text(verbatim: draft.keys.isEmpty ? "—" : ComboText.keys(draft.keys, layer: item.combo.keysLayer, in: session.layout))
            }
            .labeledContentStyle(InspectorRowStyle())
            HStack {
                if draft.combo == nil {
                    Button("Choose Output…") { model.chooseNewComboOutput() }.disabled(!model.canFinishDraft)
                } else {
                    Button("Done") { model.finishComboKeys() }.disabled(!model.canFinishDraft)
                }
                Button("Cancel") { model.cancelComboDraft() }
            }
        }
    }

    // MARK: The selected combo

    private func editor(_ item: NumberedCombo) -> some View {
        let combo = item.combo
        let layout = session.layout
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ComboNumber(item: item)
                Text(ComboText.title(combo, number: item.number)).font(.title3.weight(.semibold))
            }
            Group {
                LabeledContent("Name") { ComboNameField(model: model, session: session, combo: combo).id(combo.id) }
                LabeledContent("Keys") { chips(combo) }
                LabeledContent("Sends") { outputTile(item) }
                LabeledContent("Keys from") {
                    Picker(
                        "Keys from",
                        selection: Binding(get: { combo.keysLayer }, set: { model.setComboLayer($0, of: combo.id) })
                    ) {
                        ForEach(Array(layout.layers.enumerated()), id: \.element.id) { index, layer in
                            Text(verbatim: "\(index) · \(layer.title)").tag(index)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            .labeledContentStyle(InspectorRowStyle())
            let layer = layout.layers[safe: combo.keysLayer]?.title ?? ""
            Text(
                """
                Sextant reads the keys at these spots on \(layer). The combo fires whenever keys typing the same keycodes go \
                down together, on any layer.
                """
            )
            .font(.callout).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            comboWindow
            warnings(item)
            Divider()
            HStack {
                Button("Edit Keys…") { model.editComboKeys(combo.id) }
                Button("Delete Combo") { session.deleteCombo(combo.id) }
            }
        }
    }

    /// The keys as chips by what they show; × takes one out, down to the 2 a combo needs.
    private func chips(_ combo: Combo) -> some View {
        let layout = session.layout
        let removable = combo.keyIndices.count > 2
        return FlowChips(spacing: 4) {
            ForEach(combo.keyIndices, id: \.self) { index in
                let name = ComboText.key(index, layer: combo.keysLayer, in: layout)
                HStack(spacing: 3) {
                    Text(verbatim: name).lineLimit(1)
                    if removable {
                        Button {
                            session.toggleComboKey(index, in: combo.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(
                            String(localized: "Remove \(ComboText.spokenKey(index, layer: combo.keysLayer, in: layout))"))
                    }
                }
                .font(.callout)
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(.quaternary.opacity(0.6), in: Capsule())
                .help(String(localized: "Key \(index)"))
            }
        }
    }

    /// What the combo sends; it opens the picker as "Combo 3 › Output".
    private func outputTile(_ item: NumberedCombo) -> some View {
        let legend = Legends.legend(for: item.combo.output, layerNames: session.layout.layerNames)
        let text = ComboText.output(item.combo.output, in: session.layout)
        return Button {
            model.openComboOutputPicker(item.id)
        } label: {
            HStack(spacing: 8) {
                Text(verbatim: text)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: 32, height: 32)
                    .foregroundStyle(Tokens.capLegend.color)
                    .background {
                        RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Tokens.capTop.color)
                            .stroke(Tokens.capEdge.color, lineWidth: 0.75)
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: item.combo.output.macro == nil ? legend.name : text).lineLimit(1)
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
        .accessibilityLabel(String(localized: "Sends: \(legend.name), \(legend.qmk)"))
        .accessibilityHint(Text("Opens the keycode picker."))
    }

    /// "Window: 50 ms, every combo · Firmware Settings ›" (spec §6.4's combo term): the layout's, else the catalog's
    /// default.
    @ViewBuilder private var comboWindow: some View {
        if let term = session.layout.settingValue("comboTerm")?.doubleValue.map({ Int($0) }) {
            LabeledContent("Window") {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(term) ms, every combo")
                    Button("Firmware Settings ›") {
                        model.destination = .firmwareSettings
                        model.firmwareSettings.scrollTarget = "combo"
                    }
                    .buttonStyle(.link)
                }
            }
            .labeledContentStyle(InspectorRowStyle())
        }
    }

    /// The combo's live issues (spec §7.5), errors first.
    @ViewBuilder private func warnings(_ item: NumberedCombo) -> some View {
        let issues = LayoutIssues.check(session.layout).filter { $0.combo == item.id }
        // The inspector already names the combo.
        let suffix = " · \(ComboText.title(item.combo, number: item.number))"
        ForEach(issues) { issue in
            let text = KeyText.issueText(issue, layout: session.layout)
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: text.hasSuffix(suffix) ? String(text.dropLast(suffix.count)) : text)
                    if case .rollingNeighbors = issue.kind {
                        Text("Fast typing may set this combo off by accident.").foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle((issue.severity == .error ? Tokens.danger : Tokens.warning).color)
            }
            .font(.callout)
        }
    }
}

/// The combo's name. Return or leaving the field renames the combo it was made for, by id; blank clears the name.
private struct ComboNameField: View {
    var model: LayoutWindowModel
    var session: EditSession
    let comboID: String
    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(model: LayoutWindowModel, session: EditSession, combo: Combo) {
        self.model = model
        self.session = session
        comboID = combo.id
        _draft = State(initialValue: combo.name ?? "")
    }

    var body: some View {
        let name = session.layout.combo(id: comboID)?.name ?? ""
        TextField("Name", text: $draft, prompt: Text("Optional"))
            .labelsHidden()
            .focused($isFocused)
            .onSubmit(commit)
            .onChange(of: isFocused) { if !isFocused { commit() } }
            .onDisappear(perform: commit)
            .onChange(of: name) { draft = name }
    }

    private func commit() {
        // A layout the window has let go isn't renamed, as with the layer name.
        guard model.session === session, session.layout.combo(id: comboID) != nil else { return }
        session.renameCombo(comboID, to: draft)
    }
}

/// Chips that wrap onto more lines as the inspector narrows.
private struct FlowChips: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(
            width: rows.map(\.width).max() ?? 0, height: rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(items: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(items: [Int], width: CGFloat, height: CGFloat)] = []
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if let last = rows.last, last.width + spacing + size.width <= width {
                rows[rows.count - 1] = (last.items + [index], last.width + spacing + size.width, max(last.height, size.height))
            } else {
                rows.append(([index], size.width, size.height))
            }
        }
        return rows
    }
}
