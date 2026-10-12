import SwiftUI

/// What the sidebar selects; the destination selects the centre and the inspector (spec §2.2). Every v1 page is
/// declared here; a page without a sidebar row routes to nothing until its slice lands (ADR 0037).
public enum Destination: Hashable {
    case layer(Int)
    case firmwareSettings, combos, macros, history, appLayers
}

/// The sidebar (spec §3.6): one section per file, so each can grow on its own.
struct Sidebar: View {
    var model: LayoutWindowModel
    @Binding var layoutID: UUID?

    var body: some View {
        List(selection: selection) {
            LayoutsSection(model: model, layoutID: $layoutID)
            if let session = model.session {
                LayersSection(model: model, session: session)
                LayoutPagesSection(session: session)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { DeviceCard(model: model) }
    }

    /// Layouts are opened with their buttons, not selected.
    private var selection: Binding<Destination?> {
        Binding(
            get: { model.session == nil ? nil : model.destination },
            set: { if let destination = $0 { model.destination = destination } })
    }
}
