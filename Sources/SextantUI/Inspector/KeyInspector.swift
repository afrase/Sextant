import SextantApplication
import SextantDomain
import SwiftUI

/// The selected key (spec §5.1).
/// shortcut: read-only; the key editor (step 4) replaces it.
struct KeyInspector: View {
    var session: EditSession
    var index: Int

    var body: some View {
        let layer = session.selection.layer
        let model = KeyCapModel(layout: session.layout, layer: layer, index: index)
        KeyCap(model: model, u: 52).frame(width: 52, height: 52)
        Text(model.legend.legend.primary?.name ?? String(localized: "Key \(index)")).font(.title3.weight(.semibold))
        Text(model.legend.ownKind.title).font(.callout).foregroundStyle(.secondary)
        if session.geometry.keys.indices.contains(index) {
            Text(verbatim: "\(KeyText.position(session.geometry.key(index), in: session.geometry)) · \(String(localized: "key \(index)"))")
                .font(.callout).foregroundStyle(.secondary)
        }
        if let key = session.layout.key(layer: layer, index: index) {
            Text(Legends.qmkExpression(for: key)).font(.callout.monospaced()).textSelection(.enabled)
        }
    }
}
