import SextantApplication
import SextantDomain
import SwiftUI

/// One layout per window: sidebar, canvas and inspector (spec §3).
public struct LayoutWindow: View {
    @State private var model: LayoutWindowModel
    @Binding private var layoutID: UUID?
    @Environment(\.undoManager) private var undoManager
    @State private var windowWidth: CGFloat = 1440

    public init(library: Library, layoutID: Binding<UUID?>, onBuild: BuildHandler? = nil) {
        self.init(model: LayoutWindowModel(library: library, onBuild: onBuild), layoutID: layoutID)
    }

    /// A window over an existing model (snapshots preload it so rendering doesn't race the load).
    public init(model: LayoutWindowModel, layoutID: Binding<UUID?>) {
        _model = State(initialValue: model)
        _layoutID = layoutID
    }

    public var body: some View {
        @Bindable var model = model
        // Honest minimums (spec §3.2): 640 for the centre plus each visible column's minimum, and 640 tall with the
        // ≈52 pt toolbar. The minimum goes on the window, not the detail: on macOS 26 a detail `minWidth` counts the
        // sidebar twice. Column ideals equal their minimums so the centre gets its 640 at the smallest window.
        NavigationSplitView(columnVisibility: $model.columnVisibility) {
            Sidebar(model: model, layoutID: $layoutID)
                .navigationSplitViewColumnWidth(min: 200, ideal: 200, max: 300)
        } detail: {
            detail
                .inspector(isPresented: $model.showsInspector) {
                    InspectorSummary(model: model)
                        .inspectorColumnWidth(min: 280, ideal: 280, max: 360)
                }
                .toolbar(id: "layout") { WindowToolbar(model: model, windowWidth: windowWidth) }
        }
        .frame(minWidth: model.minimumWidth, minHeight: 640 - 52)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { windowWidth = $0 })
        .focusedSceneValue(model)
        .alert(
            Text("Delete this layer?"),
            isPresented: Binding(get: { model.layerPendingDeletion != nil }, set: { _ in model.layerPendingDeletion = nil }),
            presenting: model.layerPendingDeletion
        ) { layer in
            Button("Delete and Clear References", role: .destructive) { model.session?.deleteLayer(layer) }
            Button("Cancel", role: .cancel) {}
        } message: { layer in
            Text(model.deletionMessage(for: layer))
        }
        .task(id: layoutID) {
            let opened = await model.open(layoutID)
            if let opened, opened != layoutID { layoutID = opened }
        }
        // Closing the window ends its layout's Build & Flash and frees the layout for other windows.
        .onDisappear { Task { await model.close() } }
        .onChange(of: model.session?.id, initial: true) { model.session?.undoManager = undoManager }
        .onChange(of: model.library.entries.first?.id) {
            // A layout arrived while this window had none open (first import): open it.
            guard model.session == nil else { return }
            Task { if let opened = await model.open(layoutID) { layoutID = opened } }
        }
    }

    @ViewBuilder private var detail: some View {
        if let session = model.session {
            CanvasColumn(model: model, session: session)
                .navigationTitle(session.layout.title)
                .navigationSubtitle(model.subtitle)
        } else if let error = model.loadError {
            ContentUnavailableView(
                String(localized: "Couldn't open this layout"), systemImage: "exclamationmark.triangle",
                description: Text(error.localizedDescription))
        } else if !model.library.entries.isEmpty {
            ContentUnavailableView(
                String(localized: "Every layout is open"), systemImage: "macwindow.on.rectangle",
                description: Text("Each layout has one window. Choose one in the sidebar to bring its window forward."))
        } else {
            ContentUnavailableView(
                String(localized: "Bring your layout to Sextant"), systemImage: "keyboard",
                description: Text("Import a layout from Oryx to get started."))
        }
    }
}

private struct Sidebar: View {
    var model: LayoutWindowModel
    @Binding var layoutID: UUID?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        List(selection: layerSelection) {
            Section("Layouts") {
                ForEach(model.library.entries) { entry in
                    Button {
                        show(entry.id)
                    } label: {
                        Label(entry.title, systemImage: entry.id == model.session?.id ? "keyboard.fill" : "keyboard")
                            .fontWeight(entry.id == model.session?.id ? .semibold : .regular)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(entry.id == model.session?.id ? .isSelected : [])
                }
            }
            if let session = model.session {
                Section("Layers") {
                    ForEach(Array(session.layout.layers.enumerated()), id: \.element.id) { index, layer in
                        LayerRow(index: index, layer: layer)
                            .tag(index)
                            .contextMenu {
                                Button("Duplicate") { session.duplicateLayer(index) }
                                Button("Move Up") { session.moveLayer(from: index, to: index - 1) }.disabled(index == 0)
                                Button("Move Down") { session.moveLayer(from: index, to: index + 1) }
                                    .disabled(index == session.layout.layers.count - 1)
                                Divider()
                                Button("Delete Layer…") {
                                    session.select(layer: index)
                                    model.requestDeleteLayer()
                                }
                                .disabled(!model.canDeleteLayer)
                            }
                    }
                    Button {
                        session.addLayer()
                    } label: {
                        Label("Add Layer", systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.sidebar)
    }

    /// Opens a layout in this window, or brings forward the window that has it (one window per layout).
    private func show(_ id: UUID) {
        if id != model.session?.id, model.library.isOpen(id) {
            openWindow(id: "layout", value: id)
        } else {
            layoutID = id
        }
    }

    /// The shown layer is the sidebar's selection; layouts are opened with their buttons.
    private var layerSelection: Binding<Int?> {
        Binding(get: { model.session?.selection.layer }, set: { if let layer = $0 { model.session?.select(layer: layer) } })
    }
}

private struct LayerRow: View {
    var index: Int
    var layer: Layer

    var body: some View {
        HStack(spacing: 8) {
            LayerChip(color: layer.color, size: 10)
            Text(verbatim: "\(index)").monospacedDigit().foregroundStyle(.secondary)
            Text(layer.title)
        }
        .badge(layer.keys.filter { !$0.isTransparent }.count)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Layer \(index), \(layer.title)"))
    }
}

/// A layer's colour chip: a small rounded square, neutral on layers without a colour (spec §3.6).
struct LayerChip: View {
    var color: HexColor?
    var size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(color.map { LayerTones($0).display.color } ?? Tokens.neutralChip.color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The inspector until the key editor exists (spec §3.8, §5.1): the selected key, or a summary of the layer.
/// shortcut: read-only; the key editor (step 4) and layer actions (step 6) replace it.
private struct InspectorSummary: View {
    var model: LayoutWindowModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let session = model.session {
                    if let index = session.selection.keyIndex {
                        keySummary(session, index: index)
                    } else {
                        layerSummary(session)
                    }
                } else {
                    Text("No layout open").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    @ViewBuilder private func keySummary(_ session: EditSession, index: Int) -> some View {
        let layer = session.selection.layer
        let model = KeyCapModel(layout: session.layout, layer: layer, index: index)
        KeyCap(model: model, u: 52).frame(width: 52, height: 52)
        Text(model.legend.legend.primary?.name ?? String(localized: "Key \(index)")).font(.title3.weight(.semibold))
        Text(model.legend.ownKind.title).font(.callout).foregroundStyle(.secondary)
        if session.geometry.keys.indices.contains(index) {
            Text(verbatim: "\(KeyText.position(session.geometry.key(index), in: session.geometry)) · \(String(localized: "key \(index)"))")
                .font(.callout).foregroundStyle(.secondary)
        }
        if let key = session.layout.key(layer: layer, index: index) {
            Text(Legends.qmkExpression(for: key)).font(.callout.monospaced()).textSelection(.enabled)
        }
    }

    @ViewBuilder private func layerSummary(_ session: EditSession) -> some View {
        let index = session.selection.layer
        if let layer = session.currentLayer {
            HStack(spacing: 8) {
                LayerChip(color: layer.color, size: 12)
                Text(layer.title).font(.title3.weight(.semibold))
            }
            Text(String(localized: "Layer \(index) · \(layer.color?.hex ?? String(localized: "No colour"))"))
                .font(.callout).foregroundStyle(.secondary)
            if let activator = KeyText.activator(layout: session.layout, layer: index) {
                let source = session.layout.layers[safe: activator.layer]?.title ?? ""
                let text = String(localized: "\(activator.text) on \(source)")
                Text(text.prefix(1).uppercased() + text.dropFirst()).font(.callout).foregroundStyle(.secondary)
            }
            Divider()
            let counts = Dictionary(grouping: layer.keys, by: \.kind).mapValues(\.count)
            ForEach(KeyKind.allCases.filter { counts[$0] != nil }, id: \.self) { kind in
                LabeledContent(kind.title) { Text(verbatim: "\(counts[kind] ?? 0)").monospacedDigit() }
            }
        }
    }
}
