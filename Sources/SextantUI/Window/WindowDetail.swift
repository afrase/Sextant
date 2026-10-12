import SwiftUI

/// Detail routing (spec §2.2, §12.4): the destination's page, or the window's loading and empty states.
struct WindowDetail: View {
    var model: LayoutWindowModel
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        content
            .modifier(LayerSwitchEffects(model: model))
            // A page doesn't show the key Record Key would assign to.
            .onChange(of: model.page) { model.recorder = nil }
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
            // The palette floats over every page: Firmware settings is one of its groups.
            Group {
                switch model.page {
                case .firmwareSettings:
                    FirmwareSettingsPage(model: model, session: session)
                        .navigationTitle(session.layout.title)
                        .navigationSubtitle(
                            session.isEditedSinceRevision
                                ? String(localized: "Firmware Settings · Edited") : String(localized: "Firmware Settings"))
                // Each v1 page replaces its own line when it lands; until then no sidebar row reaches it (ADR 0037).
                case .combos: EmptyView()
                case .macros: EmptyView()
                case .history: EmptyView()
                case .appLayers: EmptyView()
                case .layer, nil:
                    CanvasColumn(model: model, session: session)
                        .navigationTitle(session.layout.title)
                        .modifier(LayerSubtitle(model: model))
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

// The two modifiers below read the selected layer in their own bodies, so a layer switch doesn't re-run WindowDetail
// and rebuild the canvas column (the board would evaluate twice per switch).

/// Choosing a layer by number or menu returns from a page to the board; Follow's layer changes don't.
private struct LayerSwitchEffects: ViewModifier {
    var model: LayoutWindowModel

    func body(content: Content) -> some View {
        content.onChange(of: model.session?.selection.layer) {
            // A layer picked by hand ends Record Key too: it would assign to the layer it started on, now hidden.
            if !model.isFollowing {
                model.showBoard()
                model.recorder = nil
            }
        }
    }
}

/// The board's window subtitle: the layer, plus " · Edited".
private struct LayerSubtitle: ViewModifier {
    var model: LayoutWindowModel

    func body(content: Content) -> some View {
        content.navigationSubtitle(model.subtitle)
    }
}
