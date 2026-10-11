import SwiftUI

/// What the sidebar selects; the destination selects the centre and the inspector (spec §2.2).
enum Destination: Hashable {
    case layer(Int)
    case firmwareSettings
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
            get: {
                guard let session = model.session else { return nil }
                return model.showsFirmwareSettings ? .firmwareSettings : .layer(session.selection.layer)
            },
            set: {
                switch $0 {
                case let .layer(index):
                    model.showsFirmwareSettings = false
                    model.session?.select(layer: index)
                case .firmwareSettings: model.showsFirmwareSettings = true
                case nil: break
                }
            })
    }
}
