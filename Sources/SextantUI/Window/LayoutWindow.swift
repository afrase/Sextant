import SextantApplication
import SwiftUI

/// One layout per window: sidebar, canvas and inspector (spec §3).
public struct LayoutWindow: View {
    @State private var model: LayoutWindowModel
    @Binding private var layoutID: UUID?
    @Environment(\.undoManager) private var undoManager
    @State private var windowWidth: CGFloat = 1440

    public init(services: SextantServices, layoutID: Binding<UUID?>) {
        self.init(model: LayoutWindowModel(services: services), layoutID: layoutID)
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
            WindowDetail(model: model)
                .inspector(isPresented: $model.showsInspector) {
                    InspectorColumn(model: model)
                        .inspectorColumnWidth(min: 280, ideal: 280, max: 360)
                }
                .toolbar(id: "layout") { WindowToolbar(model: model, windowWidth: windowWidth) }
        }
        .frame(minWidth: model.minimumWidth, minHeight: 640 - 52)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { windowWidth = $0 })
        .focusedSceneValue(model)
        .windowPresentations(model)
        .modifier(TrashLayoutDialog(model: model, layoutID: $layoutID))
        .task(id: layoutID) {
            let opened = await model.open(layoutID)
            if let opened, opened != layoutID { layoutID = opened }
        }
        // Closing the window ends its layout's Build & Flash and frees the layout for other windows; not while it
        // writes, which can't be stopped (spec §7.4).
        .windowDismissBehavior(model.buildFlash?.canStop == false ? .disabled : .automatic)
        .onDisappear { Task { await model.close() } }
        // The keyboard lighting preview: its frames while on, and its release when the window goes (ADR 0051).
        .task { await model.feedKeyboardLighting() }
        .onChange(of: model.session?.id, initial: true) {
            model.session?.undoManager = undoManager
            // The model opened a layout itself (New Layout or an import in an empty window): the window keeps it.
            if let id = model.session?.id, id != layoutID { layoutID = id }
        }
        .onChange(of: model.library.entries.first?.id) { old, _ in
            // The first layout arrived behind the Welcome (`--import`): open it. Only then: an empty window would
            // otherwise take a layout made for another window.
            guard old == nil, model.session == nil, !model.isOpening else { return }
            Task { if let opened = await model.open(layoutID) { layoutID = opened } }
        }
    }
}
