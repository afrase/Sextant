import SextantApplication
import SextantDomain
import SwiftUI

/// Whether the bench draws its precision grid (View ▸ Show Grid Behind Keyboard; spec §4.10).
enum BenchGrid {
    static let key = "showsBenchGrid"
}

/// The centre column's fixed bands (spec §3.3). Only the board area flexes, so the board never moves when the
/// selection, lens, lane or strip change.
struct CanvasColumn: View {
    var model: LayoutWindowModel
    var session: EditSession
    @AppStorage(BenchGrid.key) private var showsGrid = true

    var body: some View {
        VStack(spacing: 0) {
            CanvasHeader(model: model, session: session).frame(height: 44)
            LensLane(model: model).frame(height: 36)
            BoardView(
                session: session, mode: model.legendMode, issues: model.issueMap, pressed: model.pressedKeys,
                highlightedKind: model.highlightedKind, showsGrid: showsGrid
            )
            .environment(\.swapsKeys, model.lens == .keys)
            ContextStrip(model: model, session: session).frame(height: 76)
            BoardFooter(model: model).frame(height: 32)
        }
        .background(Bench())
    }
}

/// Layer jump menu and readout (leading), lens control (trailing).
private struct CanvasHeader: View {
    var model: LayoutWindowModel
    var session: EditSession

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 12) {
            Menu {
                ForEach(Array(session.layout.layers.enumerated()), id: \.element.id) { index, layer in
                    Toggle(
                        String(localized: "\(index) · \(layer.title)"),
                        isOn: Binding(get: { session.selection.layer == index }, set: { _ in session.select(layer: index) }))
                }
            } label: {
                HStack(spacing: 6) {
                    LayerChip(color: session.currentLayer?.color, size: 10)
                    Text(session.currentLayer?.title ?? "").fontWeight(.medium)
                }
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
            .accessibilityLabel(String(localized: "Layer: \(session.currentLayer?.title ?? "")"))
            Text(model.readout)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Picker("Lens", selection: $model.lens) {
                ForEach(Lens.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
        }
        .padding(.horizontal, 20)
    }
}
