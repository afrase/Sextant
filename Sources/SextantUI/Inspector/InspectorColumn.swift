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
        .background(ToolbarBandReveal())
    }
}

/// Shows the toolbar's band and hairline across the inspector (ADR 0060). On macOS 26 the inspector first lays out as a
/// full-height glass panel over AppKit's band for its column (the same scroll pocket and hairline the canvas shows), which
/// the glass tints darker. This masks the panel's glass to below the toolbar and its hairline so AppKit's band shows.
private struct ToolbarBandReveal: NSViewRepresentable {
    func makeNSView(context: Context) -> RevealView { RevealView() }
    func updateNSView(_ view: RevealView, context: Context) { view.needsLayout = true }

    final class RevealView: NSView {
        private let mask = CALayer()
        private weak var maskedGlass: NSView?
        private var toolbarObservation: NSKeyValueObservation?

        // Takes the mask off as it leaves, so a view that replaces it doesn't find a mask it can't tell is its own.
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if let layer = maskedGlass?.layer, layer.mask === mask { layer.mask = nil }
        }

        // The hairline's pixel is half a point on a Retina display and a whole point on others.
        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            needsLayout = true
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Showing or hiding the toolbar moves its bottom edge without resizing the inspector.
            toolbarObservation = window?.observe(\.contentLayoutRect) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.needsLayout = true }
            }
            needsLayout = true
        }

        // Runs whenever the inspector's size changes, which is when the panel's does.
        override func layout() {
            super.layout()
            guard let window, let glass = sequence(first: self as NSView, next: \.superview).first(where: { $0 is NSGlassEffectView }),
                let layer = glass.layer, layer.mask == nil || layer.mask === mask
            else { return }
            // From the panel's top down to the toolbar's bottom edge and the hairline's pixel under it.
            let panel = glass.convert(glass.bounds, to: nil)
            let cut = panel.maxY - window.contentLayoutRect.maxY + 1 / window.backingScaleFactor
            guard cut > 1, cut < panel.height else {
                layer.mask = nil
                return
            }
            maskedGlass = glass
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            mask.backgroundColor = NSColor.black.cgColor
            mask.frame = CGRect(x: 0, y: glass.isFlipped ? cut : 0, width: glass.bounds.width, height: glass.bounds.height - cut)
            layer.mask = mask
            CATransaction.commit()
        }
    }
}
