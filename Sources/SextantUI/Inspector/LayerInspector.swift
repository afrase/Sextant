import SextantApplication
import SextantDomain
import SwiftUI

/// The layer summary when no key is selected (spec §3.8).
/// shortcut: read-only; layer actions (step 6) join it.
struct LayerInspector: View {
    var session: EditSession

    var body: some View {
        let index = session.selection.layer
        if let layer = session.currentLayer {
            HStack(spacing: 8) {
                LayerChip(color: layer.color, size: 12)
                Text(layer.title).font(.title3.weight(.semibold))
            }
            Text(String(localized: "Layer \(index) · \(layer.color?.hex ?? String(localized: "No colour"))"))
                .font(.callout).foregroundStyle(.secondary)
            if let activator = KeyText.activator(layout: session.layout, layer: index) {
                let source = session.layout.layers[safe: activator.layer]?.title ?? ""
                let text = String(localized: "\(activator.text) on \(source)")
                Text(text.prefix(1).uppercased() + text.dropFirst()).font(.callout).foregroundStyle(.secondary)
            }
            Divider()
            let counts = Dictionary(grouping: layer.keys, by: \.kind).mapValues(\.count)
            ForEach(KeyKind.allCases.filter { counts[$0] != nil }, id: \.self) { kind in
                LabeledContent(kind.title) { Text(verbatim: "\(counts[kind] ?? 0)").monospacedDigit() }
            }
        }
    }
}
