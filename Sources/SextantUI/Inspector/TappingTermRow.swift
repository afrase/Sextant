import SextantApplication
import SextantDomain
import SwiftUI

/// A key's own tapping term (spec §5.1 item 7): Global or Custom, a field with a 10 ms stepper, and how far it is from
/// the global term. Custom shows the global term until the value changes; a value equal to it is stored as Global, and
/// the row stays on Custom so the stepper can step through it. A typed value commits on Return, when focus leaves or
/// when the row goes; each stepper click is one step. Like the label, it finds its layer by id when it commits.
struct TappingTermRow: View {
    var model: LayoutWindowModel
    var session: EditSession
    let layerID: String
    let index: Int
    var stored: Int?
    var focus: FocusState<KeyField?>.Binding
    @State private var custom: Bool
    @State private var draft: Int
    /// The key a typed value that isn't stored yet was typed for. It commits only onto a key with the same actions, so
    /// a swap, an undo or a button that leaves the field focused (Make Transparent, a slot's pop-up) can't put it on
    /// another key.
    @State private var typedFor: Key?

    init(model: LayoutWindowModel, session: EditSession, layerID: String, index: Int, stored: Int?, focus: FocusState<KeyField?>.Binding) {
        self.model = model
        self.session = session
        self.layerID = layerID
        self.index = index
        self.stored = stored
        self.focus = focus
        _custom = State(initialValue: stored != nil)
        _draft = State(initialValue: stored ?? session.layout.globalTappingTerm)
    }

    var body: some View {
        let global = session.layout.globalTappingTerm
        let term = stored ?? global
        LabeledContent("Tapping term") {
            VStack(alignment: .leading, spacing: 4) {
                Picker("Tapping term", selection: Binding(get: { custom }, set: choose)) {
                    Text("Global (\(global) ms)").tag(false)
                    Text("Custom").tag(true)
                }
                .labelsHidden()
                .fixedSize()
                if custom { field(global: global) }
            }
        }
        .onChange(of: focus.wrappedValue == .tappingTerm) { _, focused in if !focused { commitTyped() } }
        // Undo, redo or an import that stores a term shows it. Reaching the global term keeps Custom, so a held stepper
        // isn't removed mid-click; choosing Global, or another key, shows Global.
        .onChange(of: stored) { if stored != nil { custom = true } }
        .onChange(of: term) {
            draft = term
            typedFor = nil
        }
        .onDisappear(perform: commitTyped)
    }

    @ViewBuilder private func field(global: Int) -> some View {
        // The field sets its value on every keystroke, and again unchanged when focus moves anywhere.
        let text = Binding<Int>(get: { draft }, set: { if $0 != draft { (draft, typedFor) = ($0, key) } })
        let step = Binding<Int>(
            get: { draft },
            set: {
                typedFor = nil
                commit($0)
            })
        HStack(spacing: 4) {
            TextField("Tapping term", value: text, format: .number.grouping(.never))
                .labelsHidden()
                .controlSize(.small)
                .multilineTextAlignment(.trailing)
                .frame(width: 56)
                .focused(focus, equals: .tappingTerm)
                .onSubmit(commitTyped)
            Stepper("Tapping term", value: step, in: KeyboardLayout.tappingTermRange, step: 10)
                .labelsHidden()
                .controlSize(.small)
                .accessibilityValue(Text("\(draft) ms"))
            Text("ms").foregroundStyle(.secondary)
        }
        Text(Self.delta(draft - global)).font(.caption).foregroundStyle(.secondary)
    }

    /// Keys with a hold or a dance, and any key with its own term (imported), so a stray one can be set back to Global.
    static func shows(for key: Key) -> Bool { key.usesTappingTerm || key.tappingTerm != nil }

    /// "+20 ms from global", "−20 ms from global" or "Same as global".
    static func delta(_ ms: Int) -> String {
        ms == 0 ? String(localized: "Same as global") : String(localized: "\(ms > 0 ? "+" : "−")\(abs(ms)) ms from global")
    }

    private func choose(_ custom: Bool) {
        self.custom = custom
        guard !custom else { return }
        (draft, typedFor) = (session.layout.globalTappingTerm, nil)
        if stored != nil { commit(nil) }
    }

    /// The key the row edits, found by its layer's id.
    private var key: Key? { session.layout.layers.first { $0.id == layerID }?.keys[safe: index] }

    private func commitTyped() {
        guard let typed = typedFor else { return }
        typedFor = nil
        if key?.hasSameActions(as: typed) == true { commit(draft) }
    }

    private func commit(_ term: Int?) {
        // Not onto a session the window has already let go.
        guard model.session === session, let layer = session.layout.layers.firstIndex(where: { $0.id == layerID }) else { return }
        session.setTappingTerm(term, layer: layer, index: index)
        // Show what was stored: the domain bounds the value, and 5000 over a stored 1000 changes nothing to observe.
        draft = session.layout.key(layer: layer, index: index)?.tappingTerm ?? session.layout.globalTappingTerm
    }
}
