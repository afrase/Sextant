import SextantApplication
import SextantDomain
import SwiftUI

/// One layout per window: sidebar, canvas and inspector (spec §3).
public struct LayoutWindow: View {
    @State private var model: LayoutWindowModel
    @Binding private var layoutID: UUID?
    @Environment(\.undoManager) private var undoManager
    @State private var showInspector = true

    public init(library: Library, layoutID: Binding<UUID?>) {
        self.init(model: LayoutWindowModel(library: library), layoutID: layoutID)
    }

    /// A window over an existing model (snapshots preload it so rendering doesn't race the load).
    public init(model: LayoutWindowModel, layoutID: Binding<UUID?>) {
        _model = State(initialValue: model)
        _layoutID = layoutID
    }

    public var body: some View {
        NavigationSplitView {
            Sidebar(model: model, layoutID: $layoutID)
                .navigationSplitViewColumnWidth(min: 200, ideal: 228, max: 300)
        } detail: {
            Group {
                if let session = model.session {
                    CanvasColumn(session: session, legendMode: model.legendMode)
                        .navigationTitle(session.layout.title)
                        .navigationSubtitle(session.currentLayer?.title ?? "")
                } else if let error = model.loadError {
                    ContentUnavailableView(
                        String(localized: "Couldn't open this layout"), systemImage: "exclamationmark.triangle",
                        description: Text(error.localizedDescription))
                } else {
                    ContentUnavailableView(
                        String(localized: "Bring your layout to Sextant"), systemImage: "keyboard",
                        description: Text("Import a layout from Oryx to get started."))
                }
            }
            .frame(minWidth: 640)
            .inspector(isPresented: $showInspector) {
                Text("Select a key to edit it.")
                    .foregroundStyle(.secondary)
                    .inspectorColumnWidth(min: 280, ideal: 300, max: 360)
            }
        }
        .task(id: layoutID) {
            let opened = await model.open(layoutID)
            if let opened, opened != layoutID { layoutID = opened }
        }
        .onChange(of: model.session?.id, initial: true) { model.session?.undoManager = undoManager }
        .onChange(of: model.library.entries.first?.id) {
            // A layout arrived while this window had none open (first import): open it.
            guard model.session == nil else { return }
            Task { await model.open(layoutID) }
        }
    }
}

private struct Sidebar: View {
    var model: LayoutWindowModel
    @Binding var layoutID: UUID?

    var body: some View {
        List {
            Section("Layouts") {
                ForEach(model.library.entries) { entry in
                    Button {
                        layoutID = entry.id
                    } label: {
                        Label(entry.title, systemImage: "keyboard")
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(entry.id == model.session?.id ? Color.accentColor.opacity(0.15) : nil)
                }
            }
            if let session = model.session {
                Section("Layers") {
                    ForEach(Array(session.layout.layers.enumerated()), id: \.element.id) { index, layer in
                        Button {
                            session.select(layer: index)
                        } label: {
                            LayerRow(index: index, layer: layer, isSelected: session.selection.layer == index)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct LayerRow: View {
    var index: Int
    var layer: Layer
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(layer.color?.color ?? Tokens.neutralChip.color)
                .frame(width: 10, height: 10)
            Text(verbatim: "\(index)").monospacedDigit().foregroundStyle(.secondary)
            Text(layer.title)
            Spacer()
            Text(verbatim: "\(layer.keys.filter { !$0.isTransparent }.count)").monospacedDigit().foregroundStyle(.secondary)
        }
        .fontWeight(isSelected ? .semibold : .regular)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The centre column's fixed bands (spec §3.3). Only the board area flexes.
private struct CanvasColumn: View {
    var session: EditSession
    var legendMode: LegendMode

    var body: some View {
        VStack(spacing: 0) {
            header.frame(height: 44)
            Color.clear.frame(height: 36)  // lens lane
            BoardView(
                layout: session.layout, layer: session.selection.layer, selectedKey: session.selection.keyIndex, mode: legendMode,
                onSelect: { session.select(key: $0) }
            )
            Color.clear.frame(height: 76)  // context strip
            Color.clear.frame(height: 32)  // board footer
        }
        .background(Bench())
    }

    private var header: some View {
        HStack {
            Text(readout).font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private var readout: String {
        let l = session.selection.layer
        if l == 0 { return String(localized: "Layer 0 · base · \(session.layout.keyCount) keys") }
        let own = session.currentLayer?.keys.filter { !$0.isTransparent }.count ?? 0
        return String(localized: "Layer \(l) · \(own) own · \(session.layout.keyCount - own) inherited")
    }
}

/// The content surface behind the board: base colour with a soft radial lift (spec §4.10). Never glass.
struct Bench: View {
    var body: some View {
        ZStack {
            Tokens.benchBase.color
            RadialGradient(
                colors: [Tokens.benchLift.color, Tokens.benchBase.color], center: .init(x: 0.5, y: 0.46), startRadius: 0, endRadius: 700)
        }
    }
}
