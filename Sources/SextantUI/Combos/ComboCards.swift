import SextantApplication
import SextantDomain
import SwiftUI

/// The Combos destination's centre (spec §2.2, §6.4): the canvas in its Combos mode. A click on a key, or an arrow key
/// moving to it, selects a combo the key is in (`click(key:)`, `moveSelection(_:)`); N starts a new combo and ⌫ deletes
/// the selected one. The board only reads keys here: painting is off.
struct CombosCanvas: View {
    var model: LayoutWindowModel
    var session: EditSession

    var body: some View {
        CanvasColumn(model: model, session: session)
            .environment(\.brush, nil)
            .navigationTitle(session.layout.title)
            .navigationSubtitle(session.isEditedSinceRevision ? String(localized: "Combos · Edited") : String(localized: "Combos"))
            .onChange(of: session.layout.combos.map(\.id)) { model.endDraftOfRemovedCombo() }
            // The board passes on keys it doesn't use (spec §9.2).
            .onKeyPress(characters: ["n", "N"], phases: .down) { press in
                guard press.modifiers.isDisjoint(with: [.command, .control, .option]), model.boardPick == nil else { return .ignored }
                model.startNewCombo()
                return .handled
            }
            .onKeyPress(keys: BoardView.deleteKeys, phases: .down) { _ in
                guard model.boardPick == nil, let id = model.selectedPageCombo?.id else { return .ignored }
                session.deleteCombo(id)
                return .handled
            }
            // Edit ▸ Delete (spec §9.1), off with no combo to delete.
            .onDeleteCommand(perform: model.comboForKeys.map { id in { session.deleteCombo(id) } })
            // Another page or layout drops the keys being chosen with their pick.
            .onDisappear { model.cancelComboDraft() }
    }
}

/// "Keys from: All layers ▾" (spec §3.7), in place of the lens picker: which combos the board shows, by the layer each
/// reads its keys from. Choosing a layer shows it.
struct ComboLayerMenu: View {
    var model: LayoutWindowModel
    var session: EditSession

    var body: some View {
        let layout = session.layout
        let shown = session.selection.layer
        Menu {
            Toggle("All Layers", isOn: Binding(get: { model.combos.showsAllLayers }, set: { _ in model.showCombos(fromLayer: nil) }))
            Divider()
            ForEach(Array(layout.layers.enumerated()), id: \.element.id) { index, layer in
                let count = layout.combos.filter { $0.keysLayer == index }.count
                Toggle(
                    String(localized: "\(index) · \(layer.title) (\(count))"),
                    isOn: Binding(
                        get: { !model.combos.showsAllLayers && shown == index },
                        set: { _ in model.showCombos(fromLayer: index) }))
            }
        } label: {
            Text("Keys from: \(model.combos.showsAllLayers ? String(localized: "All layers") : layout.layers[safe: shown]?.title ?? "")")
        }
        .menuStyle(.button)
        .controlSize(.small)
        .fixedSize()
        .help(Text("Shows the combos that read their keys from a layer. A combo fires on any layer where its keys type the same keycodes."))
    }
}

/// The context strip's combo cards (spec §3.7): "J + K → Esc · keys from Main", then "+ New Combo"; or the empty state.
struct ComboCards: View {
    var model: LayoutWindowModel
    var session: EditSession

    var body: some View {
        let shown = model.shownCombos
        if session.layout.combos.isEmpty && model.combos.draft == nil {
            HStack(spacing: 12) {
                Text("No combos yet. Press two or more keys together to send another key.").foregroundStyle(.secondary)
                Button("New Combo") { model.startNewCombo() }
            }
            .font(.callout)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 20)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(shown) { card($0) }
                        newCard
                    }
                    .padding(.horizontal, 20)
                    .frame(maxHeight: .infinity)
                }
                .scrollIndicators(.never)
                .onAppear { if let id = session.selection.combo { proxy.scrollTo(id, anchor: .center) } }
                .onChange(of: session.selection.combo) { if let id = session.selection.combo { proxy.scrollTo(id, anchor: .center) } }
            }
        }
    }

    private func card(_ item: NumberedCombo) -> some View {
        let layout = session.layout
        let selected = item.id == model.selectedPageCombo?.id
        let summary = ComboText.summary(item.combo, in: layout), spoken = ComboText.spokenSummary(item.combo, in: layout)
        return Button {
            model.cancelComboDraft()
            model.selectCombo(item.id)
        } label: {
            HStack(spacing: 8) {
                ComboNumber(item: item)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: summary).font(.callout.weight(.medium)).lineLimit(1)
                    Text(verbatim: [item.combo.name, ComboText.layer(item.combo, in: layout)].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .frame(minWidth: 150, maxHeight: 60, alignment: .leading)
            .background(ContextStrip.card(dashed: false, current: selected))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(item.id)
        .accessibilityLabel(
            String(localized: "\(ComboText.title(item.combo, number: item.number)): \(spoken), \(ComboText.layer(item.combo, in: layout))")
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var newCard: some View {
        Button {
            model.startNewCombo()
        } label: {
            Label("New Combo", systemImage: "plus")
                .font(.callout.weight(.medium))
                .padding(.horizontal, 14)
                .frame(maxHeight: 60)
                .background(ContextStrip.card(dashed: true, current: false))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.combos.draft != nil)
    }
}

/// A combo's number in its colour, as the board's caps show it.
struct ComboNumber: View {
    var item: NumberedCombo

    var body: some View {
        Group {
            // Two digits as text, as on the caps (comboDecoration).
            if item.number < 10 {
                Image(systemName: "\(item.number).circle.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(item.color.color)
            } else {
                NumberDisc(text: "\(item.number)", color: item.color, diameter: 18)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The lens lane's Combos capsule (spec §3.7): New Combo, or the keys chosen so far with Choose Output or Done. The
/// pick's own capsule beside it says what a click does.
struct ComboCapsule: View {
    var model: LayoutWindowModel
    var session: EditSession

    var body: some View {
        HStack(spacing: 10) {
            if let draft = model.combos.draft, let item = model.draftCombo {
                ComboNumber(item: item)
                Text(
                    verbatim: draft.keys.isEmpty
                        ? String(localized: "No keys yet") : ComboText.keys(draft.keys, layer: item.combo.keysLayer, in: session.layout)
                )
                .lineLimit(1)
                if draft.combo == nil {
                    Button("Choose Output…") { model.chooseNewComboOutput() }.disabled(!model.canFinishDraft)
                } else {
                    Button("Done") { model.finishComboKeys() }.disabled(!model.canFinishDraft)
                }
            } else {
                Button {
                    model.startNewCombo()
                } label: {
                    Label("New Combo", systemImage: "plus")
                }
                let count = model.shownCombos.count
                Text(count == 1 ? String(localized: "1 combo") : String(localized: "\(count) combos")).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.borderless)
        .font(.callout.weight(.medium))
        .padding(.horizontal, 12)
        .frame(height: 28)
        .surface(Capsule(), interactive: true)
    }
}
