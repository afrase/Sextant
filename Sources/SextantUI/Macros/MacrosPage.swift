import SextantApplication
import SextantDomain
import SwiftUI

/// The Macros page (spec §6.3): the library on the left, the selected macro's editor on the right, and the reminder that
/// macros are plain keystrokes. Every change is one undo step.
struct MacrosPage: View {
    var model: LayoutWindowModel
    var session: EditSession

    var body: some View {
        let library = session.layout.macros
        VStack(spacing: 0) {
            header(isEmpty: library.isEmpty)
            Divider()
            if library.isEmpty {
                ContentUnavailableView {
                    Label("No macros yet", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("A macro types a sequence of keys from one key press.")
                } actions: {
                    Button("New Macro") { session.newMacro() }
                }
                .frame(maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    MacroLibraryList(model: model, session: session, library: library).frame(width: 200)
                    Divider()
                    if let locator = session.selection.macro, let macro = session.layout.macro(at: locator) {
                        MacroEditor(model: model, session: session, locator: locator, macro: macro)
                    } else {
                        Text("Select a macro").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            Divider()
            Label("Macros are stored on the keyboard as plain keystrokes. Never put a password in one.", systemImage: "lock.fill")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
        }
        .navigationTitle(session.layout.title)
        .navigationSubtitle(session.isEditedSinceRevision ? String(localized: "Macros · Edited") : String(localized: "Macros"))
        // A selection that no longer names a macro (a key edited on the board) falls back to the first.
        .onAppear { if session.selectedMacro == nil { session.selectMacro(library.first?.locator) } }
        .onDisappear { model.stopRecordingSteps() }
        .onChange(of: session.selection.macro) { _, macro in
            if model.macros.stepRecorder.map({ $0.macro != macro }) == true { model.stopRecordingSteps() }
        }
    }

    private func header(isEmpty: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "list.bullet.rectangle")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.tint))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Macros").font(.title2.weight(.semibold))
                Text("A key types a sequence of up to 24 steps").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            // The empty state has its own.
            if !isEmpty {
                Button {
                    session.newMacro()
                } label: {
                    Label("New Macro", systemImage: "plus")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

/// The library (spec §6.3): each row's title, "8 steps · 210 ms" and where it plays, or "not on a key yet".
private struct MacroLibraryList: View {
    var model: LayoutWindowModel
    var session: EditSession
    var library: [LibraryMacro]

    var body: some View {
        let layout = session.layout
        ScrollViewReader { proxy in
            list(layout)
                // New Macro, ⌘K and Assign to Key select rows the list may not show (drafts come last).
                .onChange(of: session.selection.macro, initial: true) { _, macro in if let macro { proxy.scrollTo(macro) } }
        }
    }

    private func list(_ layout: KeyboardLayout) -> some View {
        List(selection: Binding(get: { session.selection.macro }, set: { if $0 != session.selection.macro { session.selectMacro($0) } })) {
            ForEach(library) { entry in
                let isDraft = if case .draft = entry.locator { true } else { false }
                VStack(alignment: .leading, spacing: 1) {
                    Text(MacroText.title(entry.macro, at: entry.locator, in: layout)).lineLimit(1)
                    Text(MacroText.stats(entry.macro)).font(.caption).foregroundStyle(.secondary)
                    Text(MacroText.place(entry.locator, in: layout)).font(.caption).foregroundStyle(isDraft ? .tertiary : .secondary)
                        .lineLimit(1)
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
                .contextMenu {
                    Button("Assign to Key…") { model.assignMacroToKey(entry.locator) }
                    if case .key = entry.locator { Button("Remove from Key") { session.unassignMacro(entry.locator) } }
                    Divider()
                    Button("Delete Macro") { session.deleteMacro(entry.locator) }
                }
            }
        }
        .onDeleteCommand { if let locator = session.selection.macro { session.deleteMacro(locator) } }
        // Every row's natural height: without it List estimates the rows it hasn't drawn, and scrollTo stops short of far ones.
        .environment(\.defaultMinListRowHeight, 56)
        .accessibilityLabel(Text("Macros"))
    }
}

/// The selected macro: name, summary, timeline, steps, options and preview (spec §6.3).
private struct MacroEditor: View {
    var model: LayoutWindowModel
    var session: EditSession
    var locator: MacroLocator
    var macro: Macro

    private var isFull: Bool { macro.steps.count >= Macro.maxSteps }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                MacroNameField(session: session, locator: locator, stored: macro.name ?? "", prompt: placeholder).id(locator)
                Button("Assign to Key…") { model.assignMacroToKey(locator) }
                Menu {
                    if case .key = locator { Button("Remove from Key") { session.unassignMacro(locator) } }
                    Button("Delete Macro") { session.deleteMacro(locator) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel(Text("More"))
            }
            Text(MacroText.summary(macro, at: locator, in: session.layout)).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            MacroTimeline(model: model, session: session, locator: locator, macro: macro)
            stepBar
            MacroStepTable(model: model, session: session, locator: locator, macro: macro)
            HStack(spacing: 16) {
                Toggle("End with ⏎ Return", isOn: Binding(get: { macro.endsWithEnter }, set: { session.setEndsWithEnter($0, in: locator) }))
                Toggle(
                    "Hold ⌥ while typing (Unicode)",
                    isOn: Binding(get: { macro.holdsOption }, set: { session.setHoldsOption($0, in: locator) }))
            }
            .toggleStyle(.checkbox)
            Text("Types: \(MacroText.typed(macro))")
                .font(.callout.monospaced())
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(16)
    }

    private var placeholder: String {
        var unnamed = macro
        unnamed.name = nil
        return MacroText.title(unnamed, at: locator, in: session.layout)
    }

    /// Add Step and Record Steps, or what recording hears.
    private var stepBar: some View {
        let recorder = model.macros.stepRecorder.flatMap { $0.macro == locator ? $0 : nil }
        return HStack(spacing: 8) {
            Button {
                model.openStepPicker(step: nil, in: locator)
            } label: {
                Label("Add Step", systemImage: "plus")
            }
            .disabled(isFull || recorder != nil)
            if let recorder {
                Button {
                    model.stopRecordingSteps()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                HStack(spacing: 6) {
                    Circle().fill(Tokens.danger.color).frame(width: 7, height: 7).accessibilityHidden(true)
                    Text(recorder.cannotMap ? "Sextant can’t map that key. Try another." : "Listening for keys… esc stops")
                        .lineLimit(1)
                }
                .font(.callout.weight(.medium))
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Capsule().fill(Tokens.danger.color.opacity(0.15)))
            } else {
                Button {
                    model.startRecordingSteps(in: locator)
                } label: {
                    Label("Record Steps", systemImage: "record.circle")
                }
                .disabled(isFull)
                Toggle("Keep pauses", isOn: Binding(get: { model.macros.recordsPauses }, set: { model.macros.recordsPauses = $0 }))
                    .toggleStyle(.checkbox)
                    .help(Text("Record the time between keys as each step’s wait, rounded to 10 ms."))
            }
        }
        .controlSize(.small)
    }
}

/// The macro's name; empty shows what it types instead. It commits when editing ends.
private struct MacroNameField: View {
    var session: EditSession
    let locator: MacroLocator
    var stored: String
    var prompt: String
    @State private var draft: String
    @FocusState private var focused: Bool

    init(session: EditSession, locator: MacroLocator, stored: String, prompt: String) {
        self.session = session
        self.locator = locator
        self.stored = stored
        self.prompt = prompt
        _draft = State(initialValue: stored)
    }

    var body: some View {
        TextField("Name", text: $draft, prompt: Text(verbatim: prompt))
            .textFieldStyle(.plain)
            .font(.title3.weight(.semibold))
            .focused($focused)
            .onSubmit(commit)
            .onChange(of: focused) { if !focused { commit() } }
            .onChange(of: stored) { draft = stored }
            .onDisappear(perform: commit)
            .accessibilityLabel(Text("Macro name"))
    }

    private func commit() {
        guard draft != stored else { return }
        // Remove from Key moves the macro to the drafts, and the selection with it, before this field ends.
        if let target = session.layout.macro(at: locator) != nil ? locator : session.selection.macro {
            session.renameMacro(target, to: draft)
        }
    }
}

/// The steps as a table (spec §6.3): #, Key, Mods, Wait and QMK. Rows reorder by dragging; ⌫ deletes the selected one,
/// a double click opens its key in the picker.
private struct MacroStepTable: View {
    var model: LayoutWindowModel
    var session: EditSession
    var locator: MacroLocator
    var macro: Macro

    private struct Row: Identifiable {
        let id: Int
        let step: MacroStep
    }

    /// A dragged row's payload; anything else dropped on the table is ignored.
    private static let dragPrefix = "sextant-macro-step:"

    var body: some View {
        let rows = macro.steps.enumerated().map { Row(id: $0, step: $1) }
        Table(of: Row.self, selection: Binding(get: { session.selection.step }, set: { session.selectMacro(locator, step: $0) })) {
            TableColumn("#") { row in Text(verbatim: "\(row.id + 1)").monospacedDigit().foregroundStyle(.secondary) }.width(22)
            TableColumn("Key") { row in
                HStack(spacing: 4) {
                    if !MacroStep.canType(row.step.code) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Tokens.danger.color)
                            .help(Text("A macro can’t type this key"))
                    }
                    Text(verbatim: Legends.legend(for: KeyAction(code: row.step.code)).text)
                }
            }
            // Wide enough for ⌃⌥⇧⌘, which macros often hold.
            TableColumn("Mods") { row in Text(verbatim: row.step.modifiers.glyphs) }.width(54)
            TableColumn("Wait") { row in
                Text(row.step.delay == 0 ? "—" : "\(row.step.delay) ms").monospacedDigit().foregroundStyle(.secondary)
            }
            .width(60)
            TableColumn("QMK") { row in
                Text(verbatim: Legends.legend(for: KeyAction(code: row.step.code, modifiers: row.step.modifiers)).qmk)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        } rows: {
            ForEach(rows) { row in TableRow(row).draggable(Self.dragPrefix + "\(row.id)") }
                .dropDestination(for: String.self) { offset, items in
                    guard let item = items.first, item.hasPrefix(Self.dragPrefix), let from = Int(item.dropFirst(Self.dragPrefix.count))
                    else { return }
                    session.moveStep(from: from, to: offset, in: locator)
                }
        }
        .contextMenu(forSelectionType: Int.self) { selected in
            if let index = selected.first {
                Button("Change Key…") { model.openStepPicker(step: index, in: locator) }
                Button("Duplicate Step") { session.duplicateStep(at: index, in: locator) }.disabled(macro.steps.count >= Macro.maxSteps)
                Button("Delete Step") { session.deleteStep(at: index, in: locator) }
            }
        } primaryAction: { selected in
            if let index = selected.first { model.openStepPicker(step: index, in: locator) }
        }
        .onDeleteCommand { if let index = session.selection.step { session.deleteStep(at: index, in: locator) } }
        .frame(minHeight: 96)
        .accessibilityLabel(Text("Steps"))
    }
}
