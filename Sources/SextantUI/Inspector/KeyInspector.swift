import SextantApplication
import SextantDomain
import SwiftUI

/// The key editor (spec §5.1): header, issues, the inherited key, slot strip and editor, label, LED colour and
/// actions. Every change is one undoable `EditSession` call; the label and colour commit when editing ends.
struct KeyInspector: View {
    var model: LayoutWindowModel
    var session: EditSession
    var index: Int

    var body: some View {
        let layout = session.layout
        let layer = session.selection.layer
        let cap = KeyCapModel(layout: layout, layer: layer, index: index)
        let own = layout.key(layer: layer, index: index) ?? .transparent
        let layerID = layout.layers[safe: layer]?.id ?? ""
        VStack(alignment: .leading, spacing: 12) {
            header(cap, own: own)
            issues(layer: layer)
            if cap.isGhost { inherited(cap.legend, layer: layer) }
            SlotStrip(session: session, key: own, index: index)
            if !cap.isGhost {
                Text(KeyText.summary(own, layerNames: layout.layerNames)).font(.callout).foregroundStyle(.secondary)
            }
            SlotEditor(
                model: model, session: session, slot: session.selection.slot, action: own[session.selection.slot].filledAction, layer: layer
            )
            Divider()
            Text("Key").font(.headline)
            // Keyed by the key they edit, so a commit as the selection moves lands on the key it was typed for.
            Group {
                KeyLabelField(session: session, layerID: layerID, index: index, stored: own.customLabel ?? "")
                KeyColourRow(
                    session: session, layerID: layerID, index: index, stored: own.glowColor, layerColor: layout.layers[safe: layer]?.color)
            }
            .id("\(layerID)/\(index)")
            Divider()
            HStack {
                Button {
                    session.makeTransparent()
                } label: {
                    Text("Make Transparent").frame(maxWidth: .infinity)
                }
                .disabled(cap.isGhost)
                .help(Text("Make Transparent (⌘⌫)"))
                Button {
                    session.disable()
                } label: {
                    Text("Disable").frame(maxWidth: .infinity)
                }
                .disabled(cap.legend.ownKind == .disabled)
                .help(Text("Disable Key (⇧⌘⌫)"))
            }
        }
        .labeledContentStyle(InspectorRowStyle())
    }

    /// The key's live issues (spec §5.1 item 2).
    private func issues(layer: Int) -> some View {
        let layout = session.layout
        return ForEach(LayoutIssues.check(layout).filter { $0.key?.layer == layer && $0.key?.index == index }) { issue in
            Label {
                Text(KeyText.issueText(issue, layout: layout))
            } icon: {
                Image(systemName: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle((issue.severity == .error ? Tokens.danger : Tokens.warning).color)
            }
            .font(.callout)
        }
    }

    /// Cap preview, name, kind and layer, position, and the key's QMK expression (spec §5.1 item 1).
    @ViewBuilder private func header(_ cap: KeyCapModel, own: Key) -> some View {
        let resolved = cap.legend
        let primary = resolved.legend.primary
        let title =
            if cap.isGhost && !resolved.isInherited {
                KeyKind.transparent.title
            } else if resolved.legend.kind == .label, let primary {
                primary.text
            } else {
                primary?.name ?? String(localized: "Key \(index)")
            }
        let geometry = session.geometry
        let position = geometry.keys.indices.contains(index) ? KeyText.position(geometry.key(index), in: geometry) : nil
        HStack(alignment: .top, spacing: 12) {
            KeyCap(model: cap, u: 52).frame(width: 52, height: 52).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: title).font(.title3.weight(.semibold)).lineLimit(2)
                HStack(spacing: 4) {
                    badge {
                        Capsule().fill(Tokens.kind(resolved.ownKind)?.tint.color ?? .secondary).frame(width: 10, height: 3)
                        Text(resolved.ownKind.title)
                    }
                    badge {
                        LayerChip(color: session.currentLayer?.color, size: 8)
                        Text(verbatim: session.currentLayer?.title ?? "")
                    }
                }
                Text(verbatim: [position, String(localized: "key \(index)")].compactMap(\.self).joined(separator: " · "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(verbatim: Legends.qmkExpression(for: own)).font(.callout.monospaced()).textSelection(.enabled).lineLimit(2)
            Button {
                session.copyQMKExpression(index: index)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help(Text("Copy QMK Expression"))
            .accessibilityLabel(Text("Copy QMK Expression"))
            Spacer(minLength: 4)
            if let matrix = session.layout.board?.keys[safe: index] {
                Text(verbatim: "R\(matrix.matrixRow) C\(matrix.matrixColumn)").font(.caption.monospaced()).foregroundStyle(.tertiary)
            }
        }
    }

    private func badge(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 4, content: content)
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(.quaternary))
    }

    /// A transparent key says what it inherits and offers to override it (spec §4.6, §5.1 item 3).
    private func inherited(_ resolved: ResolvedLegend, layer: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(KeyText.inheritance(resolved, layout: session.layout, layer: layer)).font(.callout)
            if resolved.isInherited {
                Button(String(localized: "Override on \(session.currentLayer?.title ?? "")")) { session.overrideInherited() }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Tokens.ghostStroke.color, style: StrokeStyle(lineWidth: 1, dash: [3, 2.5]))
        }
    }
}

/// The custom label (spec §5.1): up to 10 characters, committed on Return or when focus leaves, never per keystroke.
/// It finds its layer by id when it commits, so a layer moved or deleted meanwhile can't redirect the edit.
struct KeyLabelField: View {
    var session: EditSession
    let layerID: String
    let index: Int
    var stored: String
    @State private var draft: String
    @FocusState private var focused: Bool

    init(session: EditSession, layerID: String, index: Int, stored: String) {
        self.session = session
        self.layerID = layerID
        self.index = index
        self.stored = stored
        _draft = State(initialValue: stored)
    }

    var body: some View {
        LabeledContent("Label") {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Label", text: $draft, prompt: Text("Shows the keycode"))
                    .labelsHidden()
                    .focused($focused)
                    .onSubmit(commit)
                    .onChange(of: draft) { if draft.count > 10 { draft = String(draft.prefix(10)) } }
                Text("\(draft.count)/10 · Shown in Sextant only; not sent to the keyboard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: focused) { if !focused { commit() } }
        .onChange(of: stored) { if !focused { draft = stored } }
        .onDisappear(perform: commit)
    }

    private func commit() {
        guard draft != stored, let layer = session.layout.layers.firstIndex(where: { $0.id == layerID }) else { return }
        session.setLabel(draft, layer: layer, index: index)
    }
}
