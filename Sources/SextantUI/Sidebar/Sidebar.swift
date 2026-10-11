import SwiftUI

/// What the sidebar selects; the destination selects the centre and the inspector (spec §2.2).
enum Destination: Hashable {
    case layer(Int)
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
            }
        }
        .listStyle(.sidebar)
    }

    /// Layouts are opened with their buttons, not selected.
    private var selection: Binding<Destination?> {
        Binding(
            get: { model.session.map { .layer($0.selection.layer) } },
            set: {
                switch $0 {
                case let .layer(index): model.session?.select(layer: index)
                case nil: break
                }
            })
    }
}
