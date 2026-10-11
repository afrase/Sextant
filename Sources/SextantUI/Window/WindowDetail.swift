import SwiftUI

/// Detail routing (spec §2.2, §12.4): the destination's page, or the window's loading and empty states.
struct WindowDetail: View {
    var model: LayoutWindowModel
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        content
            // Choosing a layer by number or menu returns from a page to the board; Follow's layer changes don't.
            .onChange(of: model.session?.selection.layer) {
                // A layer picked by hand ends Record Key too: it would assign to the layer it started on, now hidden.
                if !model.isFollowing {
                    model.showsFirmwareSettings = false
                    model.recorder = nil
                }
            }
            // The page doesn't show the key Record Key would assign to.
            .onChange(of: model.showsFirmwareSettings) { model.recorder = nil }
            // One alert, in the key window: every window shares the library.
            .alert(
                Text("Sextant couldn't change the library"),
                isPresented: Binding(
                    get: { activeState == .key && model.library.lastError != nil }, set: { if !$0 { model.library.lastError = nil } }),
                presenting: model.library.lastError
            ) { _ in
                Button("OK") {}
            } message: { error in
                Text(error.localizedDescription)
            }
    }

    @ViewBuilder private var content: some View {
        if let session = model.session {
            // The palette floats over both pages: Firmware settings is one of its groups.
            Group {
                if model.showsFirmwareSettings {
                    FirmwareSettingsPage(model: model, session: session)
                        .navigationTitle(session.layout.title)
                        .navigationSubtitle(
                            session.isEditedSinceRevision
                                ? String(localized: "Firmware Settings · Edited") : String(localized: "Firmware Settings"))
                } else {
                    CanvasColumn(model: model, session: session)
                        .navigationTitle(session.layout.title)
                        .navigationSubtitle(model.subtitle)
                }
            }
            .paletteHost(model)
        } else if !model.library.hasLoaded || model.isOpening {
            DelayedSpinner().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.loadError {
            ContentUnavailableView(
                String(localized: "Sextant couldn't open this layout"), systemImage: "exclamationmark.triangle",
                description: Text("\(error.localizedDescription) Choose another layout in the sidebar."))
        } else if !model.library.entries.isEmpty {
            ContentUnavailableView(
                String(localized: "Every layout is open in another window"), systemImage: "macwindow.on.rectangle",
                description: Text(
                    "Each layout has one window. Choose one in the sidebar to bring its window forward, or make a new layout (⌘N)."))
        } else {
            WelcomeView(model: model)
        }
    }
}
