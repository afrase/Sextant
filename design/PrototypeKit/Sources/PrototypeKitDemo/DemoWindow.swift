import SwiftUI
import PrototypeKit

/// A neutral, system-default window that exercises the window snapshot path:
/// sidebar (List), toolbar (segmented picker + buttons), canvas, inspector (Form with controls).
struct DemoWindow: View {
    @State var store: EditorStore
    @State var showInspector = true
    @State var device = MockDevice.frozen(at: 2.6)

    init(layer: Int = 0, selectedKey: Int? = 24) {
        let s = EditorStore()
        s.select(layer: layer)
        s.select(key: selectedKey, slot: .hold)
        _store = State(initialValue: s)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { store.selection.layer }, set: { store.select(layer: $0) })) {
                Section("Layers") {
                    ForEach(Array(store.layout.layers.enumerated()), id: \.offset) { i, layer in
                        Label {
                            Text(layer.title)
                        } icon: {
                            Image(systemName: "square.3.layers.3d").foregroundStyle(layer.color?.color ?? .secondary)
                        }
                        .tag(i)
                    }
                }
                Section("Device") {
                    Label("ZSA Voyager", systemImage: "keyboard")
                    LabeledContent("Active layer", value: store.layout.layers[device.activeLayer].title)
                }
            }
            .navigationSplitViewColumnWidth(210)
        } detail: {
            VStack(spacing: 18) {
                NeutralBoard(layout: store.layout, layer: store.selection.layer, keySize: 40, selected: store.selection.keyIndex)
                Text("\(store.layout.layers[store.selection.layer].title) · \(store.layout.keyCount) keys")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .inspector(isPresented: $showInspector) {
                inspector.inspectorColumnWidth(260)
            }
        }
        .navigationTitle(store.layout.title)
        .navigationSubtitle("Firmware \(store.layout.firmwareVersion ?? "?")")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Layer", selection: Binding(get: { store.selection.layer }, set: { store.select(layer: $0) })) {
                    ForEach(Array(store.layout.layers.enumerated()), id: \.offset) { i, l in Text(l.title).tag(i) }
                }
                .pickerStyle(.segmented)
            }
            ToolbarItemGroup {
                Button("Undo", systemImage: "arrow.uturn.backward") {}
                Button("Build", systemImage: "hammer") {}
                Button("Inspector", systemImage: "sidebar.trailing") { showInspector.toggle() }
            }
        }
    }

    @ViewBuilder var inspector: some View {
        let index = store.selection.keyIndex ?? 0
        let legend = store.legend(at: index)
        Form {
            Section("Key \(index)") {
                LabeledContent("Kind", value: legend.ownKind.title)
                ForEach(KeySlot.allCases) { slot in
                    LabeledContent(slot.title, value: legend.legend.slots[slot]?.name ?? "—")
                }
                LabeledContent("QMK", value: legend.legend.qmk).font(.system(.body, design: .monospaced))
            }
            Section("Options") {
                Toggle("Custom label", isOn: .constant(false))
                Toggle("Per-key colour", isOn: .constant(true))
                TextField("Label", text: .constant("Enter"))
            }
        }
        .formStyle(.grouped)
    }
}

/// Content for the sheet overlay demo: an Oryx import preview.
struct ImportSheet: View {
    let preview = Samples.oryxImport
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import from Oryx").font(.title2.bold())
            Text(preview.input).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            ForEach(preview.steps) { step in
                Label { VStack(alignment: .leading) { Text(step.title); Text(step.detail ?? "").font(.caption).foregroundStyle(.secondary) } }
                    icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
            }
            Divider()
            NeutralBoard(layout: preview.layout, layer: 0, keySize: 22)
                .frame(maxWidth: .infinity)
            HStack {
                Spacer()
                Button("Cancel") {}
                Button("Import") {}.buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
    }
}

/// Content for the popover overlay demo: a key's actions.
struct KeyPopover: View {
    var body: some View {
        let legend = Legends.legend(layout: Samples.layout, layer: 0, index: 24)
        VStack(alignment: .leading, spacing: 8) {
            Text("Key 24").font(.headline)
            ForEach(KeySlot.allCases) { slot in
                HStack {
                    Image(systemName: slot.symbolName).frame(width: 18)
                    Text(slot.title)
                    Spacer()
                    Text(legend.legend.slots[slot]?.name ?? "Add…").foregroundStyle(legend.legend.slots[slot] == nil ? .tertiary : .primary)
                }
            }
        }
        .padding(14)
    }
}

/// Content for the menu overlay demo.
struct LayerMenu: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(["Rename Layer…", "Duplicate Layer", "Move Left", "Move Right"], id: \.self) { item in
                Text(item).padding(.horizontal, 12).padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider().padding(.vertical, 4)
            Text("Delete Layer").foregroundStyle(.red).padding(.horizontal, 12).padding(.vertical, 4)
        }
        .padding(.vertical, 6)
    }
}

/// Glass, materials and controls side by side, to show how each snapshot path renders them.
struct GlassProbe: View {
    @State var on = true
    var body: some View {
        ZStack {
            LinearGradient(colors: [.orange, .purple], startPoint: .topLeading, endPoint: .bottomTrailing).opacity(0.5)
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Text("Glass").padding(12).glassEffect(.regular, in: .rect(cornerRadius: 12))
                    Text("Material").padding(12).background(.regularMaterial, in: .rect(cornerRadius: 12))
                    Button("Glass") {}.buttonStyle(.glass)
                    Button("Prominent") {}.buttonStyle(.glassProminent)
                }
                HStack(spacing: 16) {
                    Toggle("Switch", isOn: $on).toggleStyle(.switch)
                    Slider(value: .constant(0.4)).frame(width: 120)
                    Image(systemName: "command").font(.title)
                }
                Text("Sym+Num · hold ⏎").font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}
