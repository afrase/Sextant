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
                    case .appLayers: EmptyView()
                    case .layer:
                        if model.lens == .lighting {
                            LightingInspector(model: model, session: session)
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
    }
}
