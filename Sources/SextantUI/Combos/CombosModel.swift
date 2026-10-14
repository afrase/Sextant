import Foundation
import Observation
import SextantApplication
import SextantDomain

/// Keys being chosen on the board for a combo (spec §6.4): a new one, or an existing one's keys.
struct ComboDraft: Equatable {
    /// The combo whose keys change; nil while making a new one.
    var combo: String?
    var keys: [Int]
}

/// The Combos page's own state (spec §6.4). The selected combo lives in the session's selection, so undo brings it back.
@MainActor
@Observable
final class CombosModel {
    /// The header's "Keys from" filter: every combo, or only those that read their keys from the shown layer.
    var showsAllLayers = true
    /// Keys being chosen; set exactly while the board pick that chooses them is on.
    var draft: ComboDraft?
}

/// One combo as the page shows it: its number ("Combo 3") is its position, as in Oryx.
struct NumberedCombo: Identifiable {
    var number: Int
    var combo: Combo
    var id: String { combo.id }
    var color: Token { Tokens.combo(number - 1) }
}

/// Words for combos: cards, chips, pills and VoiceOver (spec §6.4).
enum ComboText {
    /// The combo's name, else "Combo 3".
    static func title(_ combo: Combo, number: Int) -> String { combo.name ?? String(localized: "Combo \(number)") }

    /// A key by what it shows on the layer the combo reads ("J"), else (transparent through, or disabled) by its index.
    static func key(_ index: Int, layer: Int, in layout: KeyboardLayout) -> String {
        let legend = Legends.legend(layout: layout, layer: layer, index: index).legend
        guard legend.kind != .transparent, legend.kind != .disabled, let primary = legend.primary else { return "\(index)" }
        return primary.layerName ?? CapLegendView.capText(for: primary)
    }

    /// "J + K".
    static func keys(_ keys: [Int], layer: Int, in layout: KeyboardLayout) -> String {
        keys.map { key($0, layer: layer, in: layout) }.joined(separator: " + ")
    }

    /// What the combo sends, as a cap shows it: "Esc", "⌘C", a macro's title.
    static func output(_ action: KeyAction, in layout: KeyboardLayout) -> String {
        if let macro = action.macro { return MacroText.title(macro) }
        if action.isNone || action.isTransparent { return String(localized: "Nothing") }
        let legend = Legends.legend(for: action, layerNames: layout.layerNames)
        return legend.layerName ?? CapLegendView.capText(for: legend)
    }

    /// "J + K → Esc".
    static func summary(_ combo: Combo, in layout: KeyboardLayout) -> String {
        "\(keys(combo.keyIndices, layer: combo.keysLayer, in: layout)) → \(output(combo.output, in: layout))"
    }

    /// Where the combo reads its keys: "Keys from Sym+Num".
    static func layer(_ combo: Combo, in layout: KeyboardLayout) -> String {
        String(localized: "Keys from \(layout.layers[safe: combo.keysLayer]?.title ?? "")")
    }

    /// A key for VoiceOver, by name rather than glyph ("Return", not "⏎"), else by its index.
    static func spokenKey(_ index: Int, layer: Int, in layout: KeyboardLayout) -> String {
        let legend = Legends.legend(layout: layout, layer: layer, index: index).legend
        return legend.kind == .transparent || legend.kind == .disabled ? "\(index)" : legend.primary?.name ?? "\(index)"
    }

    /// "J + K → Escape", by names for VoiceOver.
    static func spokenSummary(_ combo: Combo, in layout: KeyboardLayout) -> String {
        let keys = combo.keyIndices.map { spokenKey($0, layer: combo.keysLayer, in: layout) }.joined(separator: " + ")
        let output =
            combo.output.macro.map { MacroText.title($0) } ?? Legends.legend(for: combo.output, layerNames: layout.layerNames).name
        return "\(keys) → \(output)"
    }

    /// VoiceOver, after the key: "in combo 2: J + K → Escape".
    static func spoken(_ item: NumberedCombo, in layout: KeyboardLayout) -> String {
        String(localized: "in combo \(item.number): \(spokenSummary(item.combo, in: layout))")
    }
}

extension LayoutWindowModel {
    // MARK: What the page shows

    /// Every combo with its number, or those reading the shown layer, by the header's filter.
    var shownCombos: [NumberedCombo] {
        guard let session else { return [] }
        let layer = session.selection.layer
        return session.layout.combos.enumerated().compactMap { i, combo in
            combos.showsAllLayers || combo.keysLayer == layer ? NumberedCombo(number: i + 1, combo: combo) : nil
        }
    }

    /// The selected combo while the board shows the layer it reads (spec §6.4). On another layer its rings would sit on
    /// other keys, so the board, inspector and ⌫ treat it as unselected until that layer is shown again.
    var selectedPageCombo: NumberedCombo? {
        guard let session, let item = numberedCombo(session.selection.combo), item.combo.keysLayer == session.selection.layer
        else { return nil }
        return item
    }

    /// The combos the board draws: the selected one alone, else every shown one.
    var focusedCombos: [NumberedCombo] { selectedPageCombo.map { [$0] } ?? shownCombos }

    func numberedCombo(_ id: String?) -> NumberedCombo? {
        guard let session, let id, let i = session.layout.combos.firstIndex(where: { $0.id == id }) else { return nil }
        return NumberedCombo(number: i + 1, combo: session.layout.combos[i])
    }

    /// The draft as a combo, numbered as it will be, for the board and the cards.
    var draftCombo: NumberedCombo? {
        guard let session, let draft = combos.draft else { return nil }
        // Undo took the combo whose keys are changing: there is nothing left to change.
        if draft.combo != nil && numberedCombo(draft.combo) == nil { return nil }
        if let existing = numberedCombo(draft.combo) {
            var combo = existing.combo
            combo.keyIndices = draft.keys
            return NumberedCombo(number: existing.number, combo: combo)
        }
        let combo = Combo(id: "", keyIndices: draft.keys, layer: session.selection.layer, output: .none)
        return NumberedCombo(number: session.layout.combos.count + 1, combo: combo)
    }

    /// The Combos board's caps (spec §4.7, §6.4): members ringed and numbered in their combo's colour, every other key at
    /// 45%. A key in several combos takes the lowest number; VoiceOver hears them all.
    func comboDecoration(index: Int) -> CapDecoration {
        guard let session else { return CapDecoration() }
        let drawn = draftCombo.map { [$0] } ?? focusedCombos
        // With nothing to show, no key is a non-member.
        guard !drawn.isEmpty else { return CapDecoration() }
        let containing = drawn.filter { $0.combo.keyIndices.contains(index) }
        guard let first = containing.first else { return CapDecoration(opacity: 0.45) }
        let words = containing.map { ComboText.spoken($0, in: session.layout) }.joined(separator: "; ")
        // At 14 pt SF Symbols squeezes two digits past reading, and circles numbers only up to 50: those are text.
        let twoDigits = first.number >= 10
        let mark = CapDecoration.Mark(
            symbol: twoDigits ? "circle.fill" : "\(first.number).circle.fill", color: first.color, accessibilityText: words,
            text: twoDigits ? "\(first.number)" : nil)
        return CapDecoration(ring: first.color, number: mark)
    }

    // MARK: Selecting

    /// The header's filter: every combo (nil), or only those reading `layer`, which the board then shows.
    public func showCombos(fromLayer layer: Int?) {
        combos.showsAllLayers = layer == nil
        if let layer { session?.select(layer: layer) }
    }

    /// Selects a combo and shows the layer it reads its keys from, so the caps show those keys.
    public func selectCombo(_ id: String?) {
        guard let session else { return }
        session.selectCombo(id)
        if let combo = id.flatMap(session.layout.combo(id:)) { session.select(layer: combo.keysLayer) }
    }

    /// A click on a key selects a combo it is in: the selected one if it has the key, else the first shown one reading
    /// the shown layer, else the first shown one, whose layer the board then shows; a key in no combo clears the selection.
    func selectCombo(containing index: Int) {
        guard let session else { return }
        let shown = shownCombos.filter { $0.combo.keyIndices.contains(index) }
        if let selected = selectedPageCombo, shown.contains(where: { $0.id == selected.id }) { return }
        selectCombo((shown.first { $0.combo.keysLayer == session.selection.layer } ?? shown.first)?.id)
    }

    /// "Keys from": the combo reads another layer, and the board shows it, so the caps show the keys it now reads.
    func setComboLayer(_ layer: Int, of id: String) {
        guard let session else { return }
        session.setComboLayer(layer, in: id)
        session.select(layer: layer)
    }

    // MARK: Choosing keys

    /// New Combo (N, the strip's last card, ⌘K): clicks on the board choose 2–6 keys, then Choose Output makes the combo.
    public func startNewCombo() {
        guard let session else { return }
        if page != .combos { destination = .combos }
        session.selectCombo(nil)
        startDraft(
            ComboDraft(combo: nil, keys: []), prompt: String(localized: "Click 2–6 keys, then Choose Output · esc cancels"))
    }

    /// Edit Keys…: clicks add keys to the combo or take them out; Done keeps them.
    func editComboKeys(_ id: String) {
        guard let session, let combo = session.layout.combo(id: id) else { return }
        if page != .combos { destination = .combos }
        session.select(layer: combo.keysLayer)
        startDraft(
            ComboDraft(combo: id, keys: combo.keyIndices), prompt: String(localized: "Click keys to add or remove them · esc cancels"))
    }

    private func startDraft(_ draft: ComboDraft, prompt: String) {
        palette = nil
        recorder = nil
        // One pick at a time: the one it replaces ends as esc would end it.
        cancelBoardPick()
        combos.draft = draft
        boardPick = BoardPick(
            prompt: prompt,
            onPick: { [weak self] index in
                self?.toggleDraftKey(index)
                return false
            },
            onCancel: { [weak self] in self?.combos.draft = nil })
    }

    /// Adds the key to the draft, or takes it out; a seventh key is refused.
    public func toggleDraftKey(_ index: Int) {
        guard var draft = combos.draft else { return }
        if let at = draft.keys.firstIndex(of: index) {
            draft.keys.remove(at: at)
        } else if draft.keys.count < Combo.maxKeys {
            draft.keys.append(index)
        } else {
            announce(String(localized: "A combo takes at most 6 keys"))
            return
        }
        combos.draft = draft
    }

    /// The draft has keys enough to keep, 2–6, and its combo is still there.
    var canFinishDraft: Bool { draftCombo != nil && (2...Combo.maxKeys).contains(combos.draft?.keys.count ?? 0) }

    /// Choose Output: the picker as "Combo 3 › Output". The choice makes the combo, on the shown layer's keys, and ends
    /// the pick; closing the picker without one leaves the keys chosen.
    public func chooseNewComboOutput() {
        guard canFinishDraft, let session, let number = draftCombo?.number else { return }
        let target = AssignTarget(title: String(localized: "Combo \(number) › Output"), current: nil, accepts: Self.sendsSomething) {
            [weak self] action in
            guard let self, let draft = self.combos.draft, draft.combo == nil, self.session === session else { return }
            session.newCombo(keys: draft.keys, layer: session.selection.layer, output: action)
            self.endDraft()
        }
        openKeycodePicker(target)
    }

    /// Done: the draft's keys become the combo's, as one undo step.
    func finishComboKeys() {
        guard canFinishDraft, let session, let draft = combos.draft, let id = draft.combo else { return }
        session.setComboKeys(draft.keys, in: id)
        endDraft()
    }

    /// Ends the pick and drops the draft (esc, Cancel, leaving the page).
    func cancelComboDraft() {
        if combos.draft != nil { cancelBoardPick() }
        combos.draft = nil
    }

    /// Ends Edit Keys when undo has taken its combo: Done would have nothing to change.
    func endDraftOfRemovedCombo() {
        guard let id = combos.draft?.combo, session?.layout.combo(id: id) == nil else { return }
        cancelComboDraft()
        announce(String(localized: "The combo was removed"))
    }

    private func endDraft() {
        combos.draft = nil
        boardPick = nil
    }

    // MARK: Output

    /// The inspector's output tile: the picker as "Combo 3 › Output", replacing what the combo sends.
    func openComboOutputPicker(_ id: String) {
        guard let session, let item = numberedCombo(id) else { return }
        let target = AssignTarget(
            title: String(localized: "Combo \(item.number) › Output"), current: item.combo.output, accepts: Self.sendsSomething
        ) { action in session.setComboOutput(action, in: id) }
        openKeycodePicker(target)
    }

    /// A combo's output: Transparent and No Action would make it an empty combo.
    private static func sendsSomething(_ action: KeyAction) -> Bool { !action.isTransparent && !action.isNone }

    // MARK: Palette

    /// ⌘K's Documents group (spec §5.7): the best five combos by name and keys, any of them for "combo". One opens on the
    /// page.
    func comboDocumentItems(_ query: String) -> [PaletteItem] {
        guard let session, !query.isEmpty else { return [] }
        let layout = session.layout
        let hits = layout.combos.enumerated().compactMap { i, combo -> (score: Int, item: PaletteItem)? in
            let item = NumberedCombo(number: i + 1, combo: combo)
            let title = ComboText.title(combo, number: item.number), summary = ComboText.summary(combo, in: layout)
            let score = PaletteSearch.score(query, [title, summary, String(localized: "Combo")])
            guard score > 0 else { return nil }
            let row = PaletteItem(
                id: "document-combo-\(combo.id)", group: .documents, title: title, detail: summary,
                note: ComboText.layer(combo, in: layout), leading: .symbol("point.3.connected.trianglepath.dotted")
            ) { [weak self] in
                self?.palette = nil
                self?.destination = .combos
                self?.selectCombo(combo.id)
            }
            return (score, row)
        }
        return hits.enumerated().sorted { ($0.element.score, $1.offset) > ($1.element.score, $0.offset) }.prefix(5).map(\.element.item)
    }
}
