import SwiftUI

/// Inspector routing (spec §3.8): the destination and lens pick the inspector; each lives in its own file.
struct InspectorColumn: View {
    var model: LayoutWindowModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let session = model.session {
                    if model.lens == .lighting {
                        LightingInspector(model: model, session: session)
                    } else if let index = session.selection.keyIndex {
                        KeyInspector(session: session, index: index)
                    } else {
                        LayerInspector(model: model, session: session)
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
