import AppKit
import SextantApplication
import SextantDomain
import SwiftUI

/// The key's own LED colour on its layer (spec §5.1): a stock colour well, and No Colour to fall back to the layer's.
/// The colour panel reports every step of a drag, so a pick settles for a moment before it becomes one undo step.
struct KeyColourRow: View {
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
        guard let pending, let layer else { return }
        self.pending = nil
        if pending != stored { session.setColor(pending, layer: layer, index: index) }
    }
}

/// Key ▸ LED Colour (spec §9.1): No Colour and the layout's swatches.
struct KeyColourMenu: View {
    var session: EditSession?

    var body: some View {
        Button("No Colour") { session?.setColor(nil) }
        Divider()
        let swatch = session?.layout.swatch ?? []
        ForEach(swatch.isEmpty ? KeyboardLayout.defaultSwatch : swatch, id: \.self) { color in
            Button(color.hex) { session?.setColor(color) }
        }
    }
}

extension HexColor {
    /// A picked colour in sRGB, rounded to what `#RRGGBB` stores, so the document matches its saved form.
    init?(_ color: Color) {
        guard let c = NSColor(color).usingColorSpace(.sRGB),
            let hex = HexColor(hex: HexColor(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent).hex)
        else { return nil }
        self = hex
    }
}
