import AppKit
import SwiftUI

/// Inspector routing (spec §3.8): the destination and lens pick the inspector; each lives in its own file.
struct InspectorColumn: View {
    var model: LayoutWindowModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let session = model.session {
                    switch model.destination {
                    case .firmwareSettings: FirmwareSettingsInspector(model: model, session: session)
                    // Each v1 page replaces its own line when it lands (ADR 0037).
                    case .combos: ComboInspector(model: model, session: session)
                    case .macros: MacroStepInspector(model: model, session: session)
                    case .history: HistoryInspector(model: model)
                    case .appLayers: AppLayersInspector(model: model, session: session)
                    case .layer:
                        if model.lens == .lighting {
                            LightingInspector(model: model, session: session)
                        } else if model.lens == .heatmap {
                            HeatmapInspector(model: model, session: session)
                        } else if model.selectedKeyCount > 1 {
                            MultiKeyInspector(model: model, session: session)
                        } else if let index = session.selection.keyIndex {
                            KeyInspector(model: model, session: session, index: index)
                        } else {
                            LayerInspector(model: model, session: session)
                        }
                    }
                } else {
                    Text("No layout open").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .overlay(alignment: .top) { ToolbarBand() }
    }
}

/// The toolbar's band and hairline across the inspector. On macOS 26 the inspector first lays out full height, a glass
/// panel running up behind the toolbar, so the band the detail column shows there stopped at the inspector's edge
/// (only a drag of its divider laid it out under the band). This draws the same band over the panel's top: the window's
/// own content background and the titlebar's hairline. Nothing when the inspector already starts below the toolbar.
private struct ToolbarBand: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            let top = proxy.safeAreaInsets.top
            if top > 0 {
                VStack(spacing: 0) {
                    WindowContentBackground().frame(height: top)
                    Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1 / displayScale)
                }
                .ignoresSafeArea(edges: .top)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The material behind a window's content (what the detail column shows under the toolbar).
private struct WindowContentBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .contentBackground
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
