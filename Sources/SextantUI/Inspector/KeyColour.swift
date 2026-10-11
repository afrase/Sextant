import AppKit
import SextantApplication
import SextantDomain
import SwiftUI

/// The key's own LED colour on its layer (spec §5.1): a stock colour well, and No Colour to fall back to the layer's.
/// The colour panel reports every step of a drag, so a pick settles for a moment before it becomes one undo step.
struct KeyColourRow: View {
    var model: LayoutWindowModel
    var session: EditSession
    let layerID: String
    let index: Int
    var stored: HexColor?
    var layerColor: HexColor?
    @State private var pending: HexColor?

    var body: some View {
        LabeledContent("LED colour") {
            HStack {
                ColorPicker(
                    "LED colour",
                    selection: Binding(get: { (pending ?? stored ?? layerColor)?.color ?? .gray }, set: { pending = HexColor($0) }),
                    supportsOpacity: false
                )
                .labelsHidden()
                if stored == nil {
                    Text(layerColor == nil ? String(localized: "None") : String(localized: "Layer colour")).foregroundStyle(.secondary)
                } else {
                    Button("No Colour") {
                        pending = nil
                        if let layer { session.setColor(nil, layer: layer, index: index) }
                    }
                }
            }
        }
        .task(id: pending) {
            try? await Task.sleep(for: .milliseconds(300))
            if !Task.isCancelled { commit() }
        }
        .onDisappear(perform: commit)
    }

    /// Found by id when committing, so a layer moved or deleted meanwhile can't redirect the edit.
    private var layer: Int? { session.layout.layers.firstIndex { $0.id == layerID } }

    private func commit() {
        // Not onto a session the window has already let go.
        guard model.session === session, let pending, let layer else { return }
        self.pending = nil
        if pending != stored { session.setColor(pending, layer: layer, index: index) }
    }
}

/// Key ▸ LED Colour (spec §9.1): No Colour and the layout's swatches.
struct KeyColourMenu: View {
    var window: LayoutWindowModel?

    var body: some View {
        Button("No Colour") { window?.session?.setColor(nil) }
        Divider()
        ForEach(Array((window?.swatches ?? []).enumerated()), id: \.offset) { _, color in
            Button {
                window?.session?.setColor(color)
            } label: {
                Label {
                    Text(verbatim: color.hex)
                } icon: {
                    color.swatchImage
                }
            }
        }
    }
}
