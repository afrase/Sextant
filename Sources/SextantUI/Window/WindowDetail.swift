import SwiftUI

/// Detail routing (spec §2.2, §12.4): the destination's page, or the window's empty states.
struct WindowDetail: View {
    var model: LayoutWindowModel

    var body: some View {
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
