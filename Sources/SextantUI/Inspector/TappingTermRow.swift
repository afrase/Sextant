import SextantApplication
import SextantDomain
import SwiftUI

/// A key's own tapping term (spec §5.1 item 7): Global or Custom, a field with a 10 ms stepper, and how far it is from
/// the global term. Custom shows the global term until the value changes; a value equal to it is stored as Global. A
/// typed value commits on Return, when focus leaves or when the key changes; each stepper click is one step. Like the
/// label, it finds its layer by id when it commits.
struct TappingTermRow: View {
    var model: LayoutWindowModel
    var session: EditSession
    let layerID: String
    let index: Int
    var stored: Int?
    var focus: FocusState<KeyField?>.Binding
    @State private var custom: Bool
    @State private var draft: Int
    /// The field holds a typed value that isn't stored yet. Only that commits when the row goes, so a row that goes
    /// because its key changed (a swap, an undo) can't write its old value onto the new key.
    @State private var typed = false

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
        // Undo, redo or reaching the global value: what is stored wins.
        .onChange(of: stored) { custom = stored != nil }
        .onChange(of: term) {
            draft = term
            typed = false
        }
        .onDisappear(perform: commitTyped)
    }

    @ViewBuilder private func field(global: Int) -> some View {
        // The field sets its value on every keystroke, and again unchanged when focus moves anywhere.
        let text = Binding<Int>(get: { draft }, set: { if $0 != draft { (draft, typed) = ($0, true) } })
        let step = Binding<Int>(
            get: { draft },
            set: {
                (draft, typed) = ($0, true); commitTyped()
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
        (draft, typed) = (session.layout.globalTappingTerm, false)
        if stored != nil { commit(nil) }
    }

    private func commitTyped() {
        guard typed else { return }
        typed = false
        commit(draft)
    }

    private func commit(_ term: Int?) {
        // Not onto a session the window has already let go.
        guard model.session === session, let layer = session.layout.layers.firstIndex(where: { $0.id == layerID }) else { return }
        session.setTappingTerm(term, layer: layer, index: index)
    }
}
