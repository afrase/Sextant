import SextantApplication
import SextantDomain
import SwiftUI

/// Copy Layer To (spec §6.1, ADR 0047): puts this layer's keys on another layer of the layout, which keeps its name and
/// color, or on a new layer at the end. Each is one undo step that shows the layer copied to. Shared by the Layer menu,
/// the sidebar's context menu and the layer summary.
struct CopyLayerMenu: View {
    var window: LayoutWindowModel?
    var layer: Int

    var body: some View {
        if let session = window?.session {
            ForEach(Array(session.layout.layers.enumerated()), id: \.element.id) { index, item in
                if index != layer {
                    Button(String(localized: "Layer \(index) · \(item.title)")) {
                        window?.showBoard()
                        session.copyLayer(layer, to: index)
                    }
                }
            }
            Divider()
            Button("New Layer") {
                window?.showBoard()
                session.appendLayer(copying: layer)
            }
        }
    }
}

/// Copy To Layer for the selected keys (spec §5.4): each goes to its own place on the chosen layer.
struct CopyKeysMenu: View {
    var session: EditSession

    var body: some View {
        ForEach(Array(session.layout.layers.enumerated()), id: \.element.id) { index, item in
            if index != session.selection.layer {
                Button(String(localized: "Layer \(index) · \(item.title)")) { session.copyKeys(toLayer: index) }
            }
        }
    }
}
